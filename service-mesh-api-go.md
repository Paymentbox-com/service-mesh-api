# Service Mesh API Specification, Go mapping

How `service-mesh-api.md` maps onto Go. The specification is the authority;
this document records the representation choices and the package layout.
The contract is one package, `mesh`. Each transport is its own package that
implements the `mesh` interfaces and exports its own `New` and `NewClient`.

## Types

| specification                 | Go                                          |
|-------------------------------|---------------------------------------------|
| `Array<String>`               | `[]string`                                  |
| `Hash<String, String>`        | `map[string]string`                         |
| `Array<Byte>`                 | `[]byte`                                    |
| `kind: :route \| :topic`      | `mesh.Kind`, `KindRoute` and `KindTopic`    |
| a drain duration in seconds   | the deadline on the `context.Context` passed to `Stop` |

## Core concepts

```go
type Kind int
const (
    KindRoute Kind = iota   // replies to each request
    KindTopic               // does not reply
)

type Target struct {
    Segments []string
    Kind     Kind
    Metadata map[string]string
}

type ServiceMap struct {
    Targets []Target
}

type Message struct {
    Target   Target
    Metadata map[string]string
    Payload  []byte
}

type EndpointHandler   func(context.Context, Message) (Message, error)
type SubscriberHandler func(context.Context, Message) error

type Endpoint struct {
    Target   Target
    Metadata map[string]string
    Handler  EndpointHandler
}

type Subscriber struct {
    Target   Target
    Metadata map[string]string
    Handler  SubscriberHandler
}

type Config map[string]string
```

`Target.Equal` compares segments and kind. Metadata is configuration, not
identity.

A `Payload` passed to `Request` or `Publish`, or handed to a handler, is
owned by the receiver of the call. The runtime does not retain or mutate it
after the call, and copies if its transport library reuses buffers. `nil` and
an empty slice are both an empty payload.

The `context.Context` given to a handler is cancelled when the runtime's
drain budget expires during `Stop`.

## Client

```go
type Client interface {
    Request(ctx context.Context, msg Message, opts map[string]string) (Message, error)
    Publish(ctx context.Context, msg Message, opts map[string]string) error
    Close() error
}
```

Each transport package exports

```go
func NewClient(cfg mesh.Config, opts ...Option) (mesh.Client, error)
```

`opts` on `Request` and `Publish` is the specification's per-call
`Hash<String, String>` of transport options and may be `nil`. `ctx` governs
the local wait and cancellation. A deadline the receiving side should honor,
where a transport supports one, travels in `Metadata` or `opts` as the
transport documents.

## Runtime

```go
type Runtime interface {
    Client() Client
    Start(ctx context.Context) error
    Stop(ctx context.Context) error
    Running() bool
}
```

Each transport package exports

```go
func New(cfg mesh.Config, sm mesh.ServiceMap, endpoints []mesh.Endpoint, subscribers []mesh.Subscriber, opts ...Option) (mesh.Runtime, error)
```

`Stop` stops receiving, waits for in-flight handlers until `ctx` is done,
then closes. The caller sets the specification's drain duration with
`context.WithTimeout(ctx, drain)`. `Stop` returns `ctx.Err()` when handlers
were abandoned.

A `Runtime` is not restartable. `Start` after `Stop` returns an error the
transport defines.

Values a transport needs that cannot be strings, such as a logger or
library-specific connection options, are passed as variadic `Option`
arguments the transport package defines.

## Configuration

```go
const (
    DeploymentGroupKey = "deployment_group"
    ConsumerGroupKey   = "consumer_group"
    ConsumerGroupNone  = "none"
)
```

`DeploymentGroupKey` is required in the `Config` given to `New`; its absence
returns `ErrNoDeploymentGroup`. `NewClient` reads it only if the transport
needs it on the client side, as that transport documents.

`ConsumerGroupKey` is read from `Endpoint.Metadata`, `Subscriber.Metadata`,
or `Target.Metadata`, as the transport documents.

## Errors

```go
var (
    ErrKindMismatch      = errors.New("mesh: target kind does not match its use")
    ErrInvalidTarget     = errors.New("mesh: target cannot be carried by this transport")
    ErrNoDeploymentGroup = errors.New("mesh: config deployment_group is required")
)
```

Transports wrap these with detail; callers test with `errors.Is`. Transport
errors are returned unchanged.
