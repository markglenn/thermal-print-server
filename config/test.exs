import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :thermal_print_server, ThermalPrintServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "C8gbt92xQaw8unG7L2ngzOQkg2lv+ie/whdvDnWyUN86QFDkx9+t6zIrjrJ3L0vq",
  server: false

# Test printer config
config :thermal_print_server, :printers, %{
  "test-printer" => %{uri: "ipp://localhost:631/ipp/print"}
}

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
