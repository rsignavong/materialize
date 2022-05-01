// use crate::EvalError;
use allium_materialize::{Case as AlliumCase, Format as AlliumFormat};
// use mz_repr::adt::jsonb::JsonbRef;
// use mz_repr::strconv;

sqlfunc!(
    fn case_camel<'a>(a: &'a str) -> String {
        AlliumCase::to_camel(a)
    }
);

sqlfunc!(
    fn case_kebab<'a>(a: &'a str) -> String {
        AlliumCase::to_kebab(a)
    }
);

sqlfunc!(
    fn case_pascal<'a>(a: &'a str) -> String {
        AlliumCase::to_pascal(a)
    }
);

sqlfunc!(
    fn case_snake<'a>(a: &'a str) -> String {
        AlliumCase::to_snake(a)
    }
);

sqlfunc!(
    fn case_title<'a>(a: &'a str) -> String {
        AlliumCase::to_title(a)
    }
);

sqlfunc!(
    fn pluralize<'a>(a: &'a str) -> String {
        AlliumFormat::pluralize(a)
    }
);

sqlfunc!(
    fn singularize<'a>(a: &'a str) -> String {
        AlliumFormat::singularize(a)
    }
);

// sqlfunc!(
//     fn jsonb_to_yaml<'a>(a: JsonbRef<'a>) -> Result<String, EvalError> {
//         let mut buf = String::new();
//         strconv::format_jsonb(&mut buf, a);

//         let yaml = AlliumYaml::from_json(buf.as_str())
//             .map_err(|err| EvalError::Undefined(format!("from json: {}", err)))?;

//         Ok(yaml)
//     }
// );
