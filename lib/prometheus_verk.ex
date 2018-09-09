defmodule PrometheusVerk do
  alias Verk.Job
  alias Verk.Events.{
    JobFinished,
    JobStarted,
    JobFailed,
    QueueRunning,
    QueuePausing,
    QueuePaused
  }

  require Logger
  use GenStage

  use Prometheus.Config,
        job_duration_buckets: [
          10,
          100,
          1_000,
          10_000,
          100_000,
          300_000,
          500_000,
          750_000,
          1_000_000,
          2_000_000,
          3_000_000,
          5_000_000,
          8_000_000,
          13_000_000,
          21_000_000,
          34_000_000,
          55_000_000,
          89_000_000,
          144_000_000,
          233_000_000,
          377_000_000,
          610_000_000,
          987_000_000,
          1_597_000_000,
          2_584_000_000,
          4_181_000_000,
          6_765_000_000,
          10_946_000_000,
          17_711_000_000,
          28_657_000_000,
          46_368_000_000,
          75_025_000_000,
          121_393_000_000
        ],
        registry: :default,
        duration_unit: :microseconds

  use Prometheus.Metric

  @debug false
  @logger_tag "[Prometheus Verk]"

  def start_link() do
    GenStage.start_link(__MODULE__, :ok)
  end

  def init(_) do
    log(:info, "Initialized")

    module_name = __MODULE__

    registry = Config.registry(module_name)
    job_duration_buckets = Config.job_duration_buckets(module_name)

    duration_unit = Config.duration_unit(module_name)

    ##
    ## Histograms
    ##

    Histogram.declare(
      name: "verk_finished_job_duration_#{duration_unit}",
      help: "Time taken to fully process a job (in #{duration_unit})",
      labels: [:queue, :class],
      buckets: job_duration_buckets,
      registry: registry
    )

    Histogram.declare(
      name: "verk_failed_job_duration_#{duration_unit}",
      help: "Time taken processing before a job errored (in #{duration_unit})",
      labels: [:queue, :class],
      buckets: job_duration_buckets,
      registry: registry
    )

    ##
    ## Counters
    ##

    Counter.declare(
      name: :verk_finished_jobs_total,
      help: "Total number of processed jobs",
      labels: [:queue, :class]
    )

    Counter.declare(
      name: :verk_failed_jobs_total,
      help: "Total number of errored jobs",
      labels: [:queue, :class]
    )

    Counter.declare(
      name: :verk_started_jobs_total,
      help: "Total number of started jobs",
      labels: [:queue, :class]
    )

    Counter.declare(
      name: :verk_retried_jobs_total,
      help: "Total number of retried jobs",
      labels: [:queue, :class]
    )

    Counter.declare(
      name: :verk_stopped_queues_total,
      help: "Total number of stopped queues",
      labels: [:queue]
    )

    ##
    ## Guages
    ##

    Gauge.declare(
      name: :verk_failed_jobs,
      help: "Number of errored jobs",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_finished_jobs,
      help: "Number of finished jobs",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_running_jobs,
      help: "Number of in-progress jobs",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_dead_jobs,
      help: "Number of dead jobs (out of retries)",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_retrying_jobs,
      help: "Number of jobs to be retried",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_pending_jobs,
      help: "Number of pending jobs",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_scheduled_jobs,
      help: "Number of jobs scheduled to run",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_running_queues,
      help: "Number of running queues",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_idle_queues,
      help: "Number of running queues",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_pausing_queues,
      help: "Number of pausing queues",
      labels: [:queue]
    )

    Gauge.declare(
      name: :verk_paused_queues,
      help: "Number of paused queues",
      labels: [:queue]
    )

    ##
    ## Node setup
    ##

    {:consumer, :ok, subscribe_to: [Verk.EventProducer]}
  end

  def handle_events(events, _from, status) do
    log(:info, "Received events")
    set_gauges()
    Enum.each(events, &handle_event/1)
    {:noreply, [], status}
  end

  defp handle_event(%JobFinished{job: job} = event) do
    log(:info, "Processing finished job #{job.jid}")

    increment_counter(:verk_finished_jobs_total, job)
    store_timing(:finished_job, job, event.started_at, event.finished_at)
  end
  defp handle_event(%JobStarted{job: job} = event) do
    log(:info, "Processing started job #{job.jid}")

    increment_counter(:verk_started_jobs_total, job)

    if job.retry_count > 0 do
      increment_counter(:verk_retried_jobs_total, job)
    end
  end
  defp handle_event(%JobFailed{job: job} = event) do
    log(:info, "Processing failed job #{job.jid}")

    increment_counter(:verk_failed_jobs_total, job)
    store_timing(:failed_job, job, event.started_at, event.failed_at)
  end
  defp handle_event(%QueueRunning{queue: queue}) do
    log(:info, "Processing running queue: #{queue}")

    increment_counter(:verk_started_queues_total, queue)
  end
  defp handle_event(%QueuePausing{queue: queue}) do
    log(:info, "Processing pausing queue #{queue}")
  end
  defp handle_event(%QueuePaused{queue: queue}) do
    log(:info, "Processing paused queue #{queue}")

    increment_counter(:verk_stopped_queues_total, queue)
  end
  defp handle_event(event) do
    log(:info, "Unknown event #{inspect(event)}")
    nil
  end

  defp set_gauges() do
    Gauge.set(
      [
        name: :verk_dead_jobs,
        labels: [:dead]
      ],
      Verk.DeadSet.count!
    )

    Gauge.set(
      [
        name: :verk_retrying_jobs,
        labels: [:retry]
      ],
      Verk.RetrySet.count!
    )

    Gauge.set(
      [
        name: :verk_scheduled_jobs,
        labels: [:schedule]
      ],
      Verk.SortedSet.count!("schedule", Verk.Redis)
    )

    all_stats = Verk.QueueStats.all()

    Enum.each(all_stats, fn stats ->
      Gauge.set(
        [
          name: :verk_failed_jobs,
          labels: [stats[:queue]]
        ],
        stats[:failed_counter]
      )

      Gauge.set(
        [
          name: :verk_finished_jobs,
          labels: [stats[:queue]]
        ],
        stats[:finished_counter]
      )

      Gauge.set(
        [
          name: :verk_running_jobs,
          labels: [stats[:queue]]
        ],
        stats[:running_counter]
      )

      Gauge.set(
        [
          name: :verk_pending_jobs,
          labels: [stats[:queue]]
        ],
        Verk.Queue.count!(stats[:queue])
      )
    end)
  end

  defp increment_counter(name, %Verk.Job{} = job) do
    Counter.inc(
      name: name,
      labels: [job.queue, job.class]
    )
  end
  defp increment_counter(name, queue) do
    Counter.inc(
      name: name,
      labels: [queue]
    )
  end

  defp store_timing(histogram, job, start, ending) do
    module_name = __MODULE__
    duration_unit = Config.duration_unit(module_name)
    name = "verk_#{histogram}_duration_#{duration_unit}"
    time = time_diff(start, ending, duration_unit)
    labels = [job.queue, job.class]

    Histogram.observe(
      [
        name: name,
        labels: labels
      ],
      time
    )
  end

  defp time_diff(start, ending, unit) do
    DateTime.diff(ending, start, unit)
    |> Kernel.abs()
  end

  defp log(_level, message) do
    if @debug do
      Logger.info("#{@logger_tag} #{message}")
    end
  end
end
