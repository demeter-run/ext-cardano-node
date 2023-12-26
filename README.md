# Ext Cardano Node

The approach of this project is to allow a CRD to Cardano Node on the K8S cluster and an operator will enable the required resources to expose an Cardano Node port.

## Folder structure

* bootstrap: contains terraform resources
* operator: rust application integrated with the cluster
* scripts: useful scripts