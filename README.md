# PrometheusVerk

[Prometheus](https://prometheus.io/) exporter for
[Verk](https://github.com/edgurgel/verk).

The following metrics are exported:
- [x] job duration
- [x] job duration before failure
- [x] total number of finished jobs
- [x] total number of failed jobs
- [x] total number of started jobs
- [x] total number of retried jobs
- [x] total number of stopped queues
- [x] current number of failed jobs
- [x] current number of finished jobs
- [x] current number of running jobs
- [x] current number of dead jobs
- [x] current number of retrying jobs
- [x] current number of pending jobs
- [x] current number of scheduled jobs
- [ ] current number of running queues
- [ ] current number of idle queues
- [ ] current number of pausing queues
- [ ] current number of paused queues

## Installation

This package is not yet available through Hex, but can be installed via Git:

```elixir
def deps do
  [
    {:prometheus_verk, github: "monorkin/prometheus_verk"}
  ]
end
```

In your `application.ex` file add `PrometheusVerk` as a worker. E.g.:

```elixir
def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(MyApp.Repo, []),
      supervisor(MyApp.Web.Endpoint, []),
      supervisor(Verk.Supervisor, []),
      worker(PrometheusVerk, []) # <----- THIS
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
```

## Changelog

A changelog is kept in the [CHANGELOG.md](/CHANGELOG.md) file.

## License

This project is licensed under the MIT license. For more details reference the
[LICENSE](/LICENSE) file.

This software is provided "as is" without any kind of warranty.
