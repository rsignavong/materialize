# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

"""Utilities for launching and interacting with scratch EC2 instances."""

import asyncio
import csv
import datetime
import os
import shlex
import sys
from dataclasses import dataclass
from pathlib import Path
from subprocess import CalledProcessError
from typing import IO, Dict, List, NamedTuple, Optional, Union

import boto3
from mypy_boto3_ec2.service_resource import Instance
from mypy_boto3_ec2.type_defs import (
    InstanceNetworkInterfaceSpecificationTypeDef,
    InstanceTypeDef,
    RunInstancesRequestRequestTypeDef,
)
from prettytable import PrettyTable

from materialize import git, spawn, ui, util

# Sane defaults for internal Materialize use in the scratch account
DEFAULT_SUBNET_ID = "subnet-00bdfbd2d97eddb86"
DEFAULT_SG_ID = "sg-06f780c8e23c0d944"

SPEAKER = ui.speaker("scratch> ")
ROOT = Path(os.environ["MZ_ROOT"])
SSH_COMMAND = ["mssh", "-o", "StrictHostKeyChecking=off"]


def tags(i: Instance) -> Dict[str, str]:
    if not i.tags:
        return {}
    return {t["Key"]: t["Value"] for t in i.tags}


def instance_typedef_tags(i: InstanceTypeDef) -> Dict[str, str]:
    return {t["Key"]: t["Value"] for t in i.get("Tags", [])}


def name(tags: Dict[str, str]) -> Optional[str]:
    return tags.get("Name")


def launched_by(tags: Dict[str, str]) -> Optional[str]:
    return tags.get("LaunchedBy")


def ami_user(tags: Dict[str, str]) -> Optional[str]:
    return tags.get("ami-user", "ubuntu")


def delete_after(tags: Dict[str, str]) -> Optional[datetime.datetime]:
    unix = tags.get("scratch-delete-after")
    if not unix:
        return None
    unix = int(float(unix))
    return datetime.datetime.fromtimestamp(unix)


def instance_host(instance: Instance) -> str:
    return f"{ami_user(tags(instance))}@{instance.id}"


def print_instances(ists: List[Instance], format: str) -> None:
    field_names = [
        "Name",
        "Instance ID",
        "Public IP Address",
        "Private IP Address",
        "Launched By",
        "Delete After",
        "State",
    ]
    rows = [
        [
            name(tags),
            i.instance_id,
            i.public_ip_address,
            i.private_ip_address,
            launched_by(tags),
            delete_after(tags),
            i.state["Name"],
        ]
        for (i, tags) in [(i, tags(i)) for i in ists]
    ]
    if format == "table":
        pt = PrettyTable()
        pt.field_names = field_names
        pt.add_rows(rows)
        print(pt)
    elif format == "csv":
        w = csv.writer(sys.stdout)
        w.writerow(field_names)
        w.writerows(rows)
    else:
        raise RuntimeError("Unknown format passed to print_instances")


def launch(
    *,
    key_name: Optional[str],
    instance_type: str,
    ami: str,
    ami_user: str,
    tags: Dict[str, str],
    display_name: Optional[str] = None,
    subnet_id: Optional[str] = None,
    size_gb: int,
    security_group_id: str,
    instance_profile: Optional[str],
    nonce: str,
    delete_after: datetime.datetime,
) -> Instance:
    """Launch and configure an ec2 instance with the given properties."""

    if display_name:
        tags["Name"] = display_name
    tags["scratch-delete-after"] = str(delete_after.timestamp())
    tags["nonce"] = nonce
    tags["git_ref"] = git.describe()
    tags["ami-user"] = ami_user

    network_interface: InstanceNetworkInterfaceSpecificationTypeDef = {
        "AssociatePublicIpAddress": True,
        "DeviceIndex": 0,
        "Groups": [security_group_id],
    }
    if subnet_id:
        network_interface["SubnetId"] = subnet_id

    SPEAKER(f"launching instance {display_name or '(unnamed)'}")
    with open(ROOT / "misc" / "load-tests" / "provision.bash") as f:
        provisioning_script = f.read()
    kwargs: RunInstancesRequestRequestTypeDef = {
        "MinCount": 1,
        "MaxCount": 1,
        "ImageId": ami,
        "InstanceType": instance_type,  # type: ignore
        "UserData": provisioning_script,
        "TagSpecifications": [
            {
                "ResourceType": "instance",
                "Tags": [{"Key": k, "Value": v} for (k, v) in tags.items()],
            }
        ],
        "NetworkInterfaces": [network_interface],
        "BlockDeviceMappings": [
            {
                "DeviceName": "/dev/sda1",
                "Ebs": {
                    "VolumeSize": size_gb,
                    "VolumeType": "gp3",
                },
            }
        ],
        "MetadataOptions": {
            # Allow Docker containers to access IMDSv2.
            "HttpPutResponseHopLimit": 2,
        },
    }
    if key_name:
        kwargs["KeyName"] = key_name
    if instance_profile:
        kwargs["IamInstanceProfile"] = {"Name": instance_profile}
    i = boto3.resource("ec2").create_instances(**kwargs)[0]

    return i


class CommandResult(NamedTuple):
    status: str
    stdout: str
    stderr: str


async def setup(
    i: Instance,
    git_rev: str,
) -> None:
    def is_ready(i: Instance) -> bool:
        return bool(
            i.public_ip_address and i.state and i.state.get("Name") == "running"
        )

    done = False
    async for remaining in ui.async_timeout_loop(60, 5):
        SPEAKER(f"Waiting for instance to become ready: {remaining}s remaining")
        i.reload()
        if is_ready(i):
            done = True
            break

    done = False
    async for remaining in ui.async_timeout_loop(180, 5):
        SPEAKER(f"Checking whether SSH works yet: {remaining}s remaining")
        try:
            mssh(i, "true")
            done = True
            break
        except CalledProcessError:
            continue

    if not done:
        raise RuntimeError(
            "Instance did not finish setup in a reasonable amount of time"
        )

    if not done:
        raise RuntimeError(
            f"Instance {i} did not become ready in a reasonable amount of time"
        )

    mkrepo(i, git_rev)


def mkrepo(i: Instance, rev: str) -> None:
    mssh(i, "git init --bare materialize/.git")
    spawn.runv(
        [
            "git",
            "push",
            f"{instance_host(i)}:materialize/.git",
            # Explicit refspec is required if the host repository is in detached
            # HEAD mode.
            "HEAD:refs/heads/scratch",
        ],
        cwd=ROOT,
        env=dict(os.environ, GIT_SSH_COMMAND=" ".join(SSH_COMMAND)),
    )
    rev = git.rev_parse(rev)
    mssh(
        i,
        f"cd materialize && git config core.bare false && git checkout {rev}",
    )


@dataclass
class MachineDesc:
    name: str
    launch_script: Optional[str]
    instance_type: str
    ami: str
    tags: Dict[str, str]
    size_gb: int
    checkout: bool = True
    ami_user: str = "ubuntu"


def launch_cluster(
    descs: List[MachineDesc],
    *,
    nonce: Optional[str] = None,
    subnet_id: str = DEFAULT_SUBNET_ID,
    key_name: Optional[str] = None,
    security_group_id: str = DEFAULT_SG_ID,
    instance_profile: Optional[str] = None,
    extra_tags: Dict[str, str] = {},
    delete_after: datetime.datetime,
    git_rev: str = "HEAD",
    extra_env: Dict[str, str] = {},
) -> List[Instance]:
    """Launch a cluster of instances with a given nonce"""

    if not nonce:
        nonce = util.nonce(8)

    instances = [
        launch(
            key_name=key_name,
            instance_type=d.instance_type,
            ami=d.ami,
            ami_user=d.ami_user,
            tags={**d.tags, **extra_tags},
            display_name=f"{nonce}-{d.name}",
            size_gb=d.size_gb,
            subnet_id=subnet_id,
            security_group_id=security_group_id,
            instance_profile=instance_profile,
            nonce=nonce,
            delete_after=delete_after,
        )
        for d in descs
    ]

    loop = asyncio.get_event_loop()
    loop.run_until_complete(
        asyncio.gather(
            *(
                setup(i, git_rev if d.checkout else "HEAD")
                for (i, d) in zip(instances, descs)
            )
        )
    )

    hosts_str = "".join(
        (f"{i.private_ip_address}\t{d.name}\n" for (i, d) in zip(instances, descs))
    )
    for i in instances:
        mssh(i, "sudo tee -a /etc/hosts", stdin=hosts_str.encode())

    env = " ".join(f"{k}={shlex.quote(v)}" for k, v in extra_env.items())
    for (i, d) in zip(instances, descs):
        if d.launch_script:
            mssh(
                i,
                f"cd materialize && {env} nohup bash -c {shlex.quote(d.launch_script)} &> mzscratch.log &",
            )

    return instances


def whoami() -> str:
    return boto3.client("sts").get_caller_identity()["UserId"].split(":")[1]


def get_instances_by_tag(k: str, v: str) -> List[InstanceTypeDef]:
    return [
        i
        for r in boto3.client("ec2").describe_instances()["Reservations"]
        for i in r["Instances"]
        if instance_typedef_tags(i).get(k) == v
    ]


def get_old_instances() -> List[InstanceTypeDef]:
    def is_running(i: InstanceTypeDef) -> bool:
        return i["State"]["Name"] == "running"

    def is_old(i: InstanceTypeDef) -> bool:
        delete_after = instance_typedef_tags(i).get("scratch-delete-after")
        if delete_after is None:
            return False
        delete_after = float(delete_after)
        return datetime.datetime.utcnow().timestamp() > delete_after

    return [
        i
        for r in boto3.client("ec2").describe_instances()["Reservations"]
        for i in r["Instances"]
        if is_running(i) and is_old(i)
    ]


def mssh(
    instance: Instance,
    command: str,
    *,
    stdin: Union[None, int, IO[bytes], bytes] = None,
) -> None:
    """Runs a command over SSH via EC2 Instance Connect."""
    host = instance_host(instance)
    # The actual invocation of SSH that `spawn.runv` wants to print is
    # unreadable quoted garbage, so we do our own printing here before the shell
    # quoting.
    if command:
        print(f"{host}$ {command}", file=sys.stderr)
        # Eval and quote to work around:
        # https://github.com/aws/aws-ec2-instance-connect-cli/pull/26
        command = f"eval {shlex.quote(command)}"
    else:
        print(f"$ mssh {host}")
    spawn.runv(
        [
            *SSH_COMMAND,
            f"{host}",
            command,
        ],
        stdin=stdin,
        print_to=open(os.devnull, "w"),
    )
