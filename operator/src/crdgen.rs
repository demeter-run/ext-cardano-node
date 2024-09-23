use std::env::args;

use kube::CustomResourceExt;
use operator::controller;

fn main() {
    let args: Vec<String> = args().collect();
    if args.len() > 1 {
        if args[1] == "json" {
            print!(
                "{}",
                serde_json::to_string_pretty(&controller::CardanoNodePort::crd()).unwrap()
            );
            return;
        }
    }

    print!(
        "{}",
        serde_yaml::to_string(&controller::CardanoNodePort::crd()).unwrap()
    )
}
