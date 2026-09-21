# Mainnet P2P baseline

These files provide the mainnet settings used when an instance opts into a
custom P2P topology. They preserve the node's bootstrap peers, ledger-peer
activation, peer snapshot, tracing, and protocol configuration.

`topology.json` supplies the P2P baseline. The module adds an instance's
configured local roots to it as one non-advertised root group, with a valency
equal to the number of access points.

The genesis, checkpoint, and peer-snapshot paths are absolute because the
module mounts only `config.json` and `topology.json` at `/configuration`. The
node reads the referenced network files from `/opt/cardano/config/mainnet`.
