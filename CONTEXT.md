# Shared configuration registry

The registry shares typed configuration data between Nix configurations. Each project defines the shared options and chooses which configurations take part.

## Language

**Registry**:
Shared configuration data formed from central definitions and node contributions under one schema.
_Avoid_: Handle, service discovery service

**Schema**:
The shared option declarations, including their types, defaults, and derived values.
_Avoid_: Model, infrastructure schema

**Node**:
A named, evaluated configuration included in a registry. Its name identifies its contributions and need not be a hostname.
_Avoid_: Participant, host, source repository, node module

**Contribution**:
Option definitions supplied by a node or a central module. A contribution can contain only part of a shared record.
_Avoid_: Publication, registration

**Central data**:
Shared data from central definitions and schema defaults, without node contributions. Central definitions have the same precedence as node definitions unless an explicit priority changes it.
_Avoid_: Global defaults, central store

**Combined data**:
Shared data from central definitions and all node contributions, merged according to the schema. A record can be complete in the combined data even when individual contributions are incomplete.
_Avoid_: Combined view, global state
