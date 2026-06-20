import Config

# Route every request through the test plug instead of the network. The base
# URLs stay hardcoded in the client; only the transport is swapped.
config :demografix, :req_options, plug: {Req.Test, Demografix}
