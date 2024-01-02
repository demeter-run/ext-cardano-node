resource "kubernetes_manifest" "customresourcedefinition_cardanonodeports_demeter_run" {
  manifest = {
    "apiVersion" = "apiextensions.k8s.io/v1"
    "kind" = "CustomResourceDefinition"
    "metadata" = {
      "name" = "cardanonodeports.demeter.run"
    }
    "spec" = {
      "group" = "demeter.run"
      "names" = {
        "categories" = []
        "kind" = "CardanoNodePort"
        "plural" = "cardanonodeports"
        "shortNames" = []
        "singular" = "cardanonodeport"
      }
      "scope" = "Namespaced"
      "versions" = [
        {
          "additionalPrinterColumns" = [
            {
              "jsonPath" = ".spec.network"
              "name" = "Network"
              "type" = "string"
            },
            {
              "jsonPath" = ".spec.version"
              "name" = "Version"
              "type" = "number"
            },
            {
              "jsonPath" = ".status.endpointUrl"
              "name" = "Endpoint URL"
              "type" = "string"
            },
          ]
          "name" = "v1alpha1"
          "schema" = {
            "openAPIV3Schema" = {
              "description" = "Auto-generated derived type for CardanoNodePortSpec via `CustomResource`"
              "properties" = {
                "spec" = {
                  "properties" = {
                    "network" = {
                      "enum" = [
                        "mainnet",
                        "preprod",
                        "preview",
                        "sanchonet",
                      ]
                      "type" = "string"
                    }
                    "version" = {
                      "format" = "uint8"
                      "minimum" = 0
                      "type" = "integer"
                    }
                  }
                  "required" = [
                    "network",
                    "version",
                  ]
                  "type" = "object"
                }
                "status" = {
                  "nullable" = true
                  "properties" = {
                    "endpointUrl" = {
                      "nullable" = true
                      "type" = "string"
                    }
                  }
                  "type" = "object"
                }
              }
              "required" = [
                "spec",
              ]
              "title" = "CardanoNodePort"
              "type" = "object"
            }
          }
          "served" = true
          "storage" = true
          "subresources" = {
            "status" = {}
          }
        },
      ]
    }
  }
}
