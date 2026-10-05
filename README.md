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
`topology.external_local_root_groups`. Each entry renders as its own
non-advertised local-root group after the fleet group, with a valency equal to
its number of access points, so it can be added or removed without touching the
fleet mesh. External groups do not create a `nodes-<salt>` Service.

```hcl
topology = {
  local_roots = [ /* fleet peers */ ]
  external_local_root_groups = [
    {
      access_points = [
        { address = "relay.peer-operator.example", port = 3001 },
      ]
    },
  ]
}
```

## Pool capacity inputs

Five opt-in inputs support running a pool of interchangeable nodes behind one
Service. An instance or Service that sets none of them renders exactly as
before.

Per instance (`instances`):

| Input | Default | Effect |
| --- | --- | --- |
| `termination_grace_period_seconds` | `null` | Seconds the pod gets after SIGTERM. Must be a positive whole number. `null` keeps the Kubernetes default (30). |
| `spread_hosts` | `false` | Adds a *preferred* pod anti-affinity (weight 100, topology key `kubernetes.io/hostname`, selecting `role=node` and the instance's `network`), next to any node affinity. A displaced pod doubles up with another node when no other host has room. |
| `spread_hosts_required` | `false` | Makes that anti-affinity *required* instead of preferred, and implies `spread_hosts`. A displaced pod waits Pending until a host without a node of its network has room, so set it only where the node group replaces a lost host and keeps at least one host per node. |

Per Service (`services`):

| Input | Default | Effect |
| --- | --- | --- |
| `headless` | `false` | Renders the Service with `cluster_ip = "None"` and `publish_not_ready_addresses = false`, keeping its selector and the `n2c` (3307) and `n2n` (3000) ports. DNS and the SRV records `_n2c._tcp.<name>.<namespace>.svc.cluster.local` then list Ready pods only. |
| `pdb_max_unavailable` | `null` | Creates a `policy/v1` PodDisruptionBudget named after the Service, with this `maxUnavailable` and the Service's selector. Must be a non-negative whole number. |

```hcl
instances = {
  "mainnet-pool-a" = {
    # existing instance settings
    termination_grace_period_seconds = 600
    spread_hosts                     = true
  }
}

services = {
  "mainnet-pool" = {
    name                = "node-mainnet-pool"
    network             = "mainnet"
    release             = "pool"
    node_version        = "11.0.1"
    active_salt         = ""
    headless            = true
    pdb_max_unavailable = 1
  }
}
```

A headless pool Service is the opposite of the `nodes-<salt>` peer Services,
which keep publishing not-ready addresses so the mesh can still resolve a
recovering peer. Switching an existing Service to `headless` changes its
cluster IP, which Kubernetes cannot do in place: Terraform replaces the
Service. Add a new Service entry rather than flipping an existing one.
