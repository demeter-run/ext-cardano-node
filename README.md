# Ext Cardano Node

The approach of this project is to allow a CRD to Cardano Node on the K8S cluster and an operator will enable the required resources to expose an Cardano Node port.

## Folder structure

* bootstrap: contains terraform resources
* operator: rust application integrated with the cluster
* scripts: useful scripts

## P2P local roots

An instance can opt into an in-cluster P2P mesh with typed local roots:

```hcl
instances = {
  "mainnet-example-a" = {
    # existing instance settings
    topology = {
      local_roots = [
        {
          address = "node-mainnet-b-0.nodes-b.example-namespace.svc.cluster.local"
          port    = 3000
        },
      ]
    }
  }
}
```

Each opt-in instance gets a topology ConfigMap and a headless
`nodes-<salt>` Service. The Service selects only that node instance, so the
StatefulSet pod address is stable. The module writes all supplied roots into
one non-advertised local-root group and sets its valency to the number of
access points. Omitting `topology.local_roots` preserves the prior instance
shape.

Peers outside the fleet, such as another operator's relay, go in
`topology.extra_local_root_groups`. Each entry renders as its own
non-advertised local-root group after the fleet group, with a valency equal to
its number of access points, so it can be added or removed without touching the
fleet mesh. Extra groups do not create a `nodes-<salt>` Service.

```hcl
topology = {
  local_roots = [ /* fleet peers */ ]
  extra_local_root_groups = [
    {
      access_points = [
        { address = "relay.peer-operator.example", port = 3001 },
      ]
    },
  ]
}
```
