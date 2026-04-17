import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/thermal_print_server start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :thermal_print_server, ThermalPrintServerWeb.Endpoint, server: true
end

# SQS and printer configuration (all environments, when env vars present)
if queue_url = System.get_env("PRINT_QUEUE_URL") do
  config :thermal_print_server,
    sqs_queue_url: queue_url,
    aws_region: System.get_env("AWS_REGION", "us-east-1")
end

if cups_uri = System.get_env("CUPS_URI") do
  config :thermal_print_server, :cups_uri, cups_uri
end

if print_bucket = System.get_env("PRINT_BUCKET") do
  config :thermal_print_server, :print_bucket, print_bucket
end

if site_id = System.get_env("SITE_ID") do
  config :thermal_print_server, :site_id, site_id
end

if site_name = System.get_env("SITE_NAME") do
  config :thermal_print_server, :site_name, site_name
end

if heartbeat_interval = System.get_env("HEARTBEAT_INTERVAL") do
  case Integer.parse(heartbeat_interval) do
    {seconds, ""} when seconds > 0 ->
      config :thermal_print_server, :heartbeat_interval, seconds

    _ ->
      IO.warn("Invalid HEARTBEAT_INTERVAL #{inspect(heartbeat_interval)}, using default (60s)")
  end
end

# Build printer map from PRINTER_*_NAME / PRINTER_*_URI env vars
printers =
  System.get_env()
  |> Enum.filter(fn {k, _v} -> String.match?(k, ~r/^PRINTER_\d+_NAME$/) end)
  |> Enum.map(fn {name_key, name_val} ->
    num = String.replace(name_key, ~r/^PRINTER_(\d+)_NAME$/, "\\1")
    uri = System.get_env("PRINTER_#{num}_URI", "ipp://localhost:631/ipp/print")
    {name_val, %{uri: uri}}
  end)
  |> Map.new()

if map_size(printers) > 0 do
  config :thermal_print_server, :printers, printers
end

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: System.get_env("AWS_REGION", "us-east-1")

# Per-service endpoint overrides (ElasticMQ for SQS, MinIO for S3)
if sqs_endpoint = System.get_env("AWS_SQS_ENDPOINT") do
  uri = URI.parse(sqs_endpoint)

  config :ex_aws, :sqs,
    scheme: "#{uri.scheme}://",
    host: uri.host,
    port: uri.port
end

if s3_endpoint = System.get_env("AWS_S3_ENDPOINT") do
  uri = URI.parse(s3_endpoint)

  config :ex_aws, :s3,
    scheme: "#{uri.scheme}://",
    host: uri.host,
    port: uri.port
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :thermal_print_server, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :thermal_print_server, ThermalPrintServerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :thermal_print_server, ThermalPrintServerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :thermal_print_server, ThermalPrintServerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
