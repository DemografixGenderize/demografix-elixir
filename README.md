# Demografix

Run demographic analysis over names — predicted gender, age, and nationality — from one Elixir client. The package covers [genderize.io](https://genderize.io), [agify.io](https://agify.io), and [nationalize.io](https://nationalize.io).

## Install

Add `:demografix` to the deps in `mix.exs`:

```elixir
def deps do
  [
    {:demografix, "~> 0.1"}
  ]
end
```

Then run `mix deps.get`. Requires Elixir 1.18 or later.

## Quickstart

Construct a client, run a batch over a list, read the predictions, and read the quota.

```elixir
client = Demografix.new("YOUR_API_KEY")

{:ok, batch} = Demografix.genderize_batch(client, ["peter", "lois", "kim", "michael"])

# Aggregate the list into a gender split.
split = Enum.frequencies_by(batch.results, & &1.gender)
# => %{"male" => 2, "female" => 2}

batch.quota.remaining
# => 24987
```

The client is a struct. `Demografix.new/2` takes a required API key and options. The same key works across all three services. A `nil` or blank key raises `ArgumentError`.

```elixir
Demografix.new("YOUR_API_KEY")
Demografix.new("YOUR_API_KEY", timeout: 5_000) # custom receive timeout in ms (default 10_000)
```

Every function returns `{:ok, result}` or `{:error, %Demografix.Error{}}`. The bang variants (`genderize!/3` and the rest) return the result or raise.

## genderize

Predict gender. A single call returns one result; the batch call summarizes a list.

```elixir
{:ok, result} = Demografix.genderize(client, "peter")
result.gender       # => "male"
result.probability  # => 1.0
result.count        # => 1352696

{:ok, batch} = Demografix.genderize_batch(client, ["peter", "lois", "kim"])
Enum.frequencies_by(batch.results, & &1.gender)
# => %{"male" => 1, "female" => 2}
```

`gender` is `"male"`, `"female"`, or `nil`. A name with no match returns `nil` with `probability` `0.0` and `count` `0`. That is a normal result, not an error.

## agify

Predict age. Aggregate the batch into an age distribution.

```elixir
{:ok, result} = Demografix.agify(client, "michael")
result.age  # => 57

{:ok, batch} = Demografix.agify_batch(client, ["michael", "matthew", "jane"])

ages = batch.results |> Enum.map(& &1.age) |> Enum.reject(&is_nil/1)
Enum.sum(ages) / length(ages)
# => average predicted age across the list
```

`age` is an integer or `nil`. A name with no match returns `nil` with `count` `0`.

## nationalize

Predict nationality. Each prediction holds up to five country candidates in descending probability. Aggregate the batch into a nationality mix.

```elixir
{:ok, result} = Demografix.nationalize(client, "nguyen")
top = hd(result.country)
top.country_id   # => "VN"
top.probability  # => 0.891132

{:ok, batch} = Demografix.nationalize_batch(client, ["nguyen", "smith", "garcia"])

batch.results
|> Enum.flat_map(fn p -> p.country |> Enum.take(1) |> Enum.map(& &1.country_id) end)
|> Enum.frequencies()
# => the top-country mix across the list
```

A name with no match returns an empty `country` list.

## country_id

`genderize` and `agify` accept a `country_id:` option, an ISO 3166-1 alpha-2 code that scopes the prediction. Nationalize does not take one. The code is echoed back uppercase on the result.

```elixir
{:ok, result} = Demografix.genderize(client, "kim", country_id: "US")
result.country_id  # => "US"

{:ok, batch} = Demografix.agify_batch(client, ["kim", "andrea"], country_id: "US")
```

## Quota

Every result and every error carries a `Demografix.Quota` read from the rate-limit response headers. Read it off the returned value; it is never cached on the client.

| Field | Meaning |
|---|---|
| `limit` | names allowed in the current window |
| `remaining` | names left in the current window |
| `reset` | seconds until the window resets |

```elixir
{:ok, result} = Demografix.genderize(client, "peter")
result.quota.limit      # => 25000
result.quota.remaining  # => 24987
result.quota.reset      # => 1314000
```

## Errors

Non-2xx responses return `{:error, %Demografix.Error{}}`. The struct carries a typed `:kind`, the HTTP `:status`, the server `:message`, and the `:quota` when the headers are present. Match on `:kind` to branch.

| `:kind` | Status | Raised when |
|---|---|---|
| `:auth` | 401 | The API key is invalid. |
| `:subscription` | 402 | The freebie expired or the subscription is not active. |
| `:validation` | 422 | Parameters are invalid. Also raised client-side for more than 10 names. |
| `:rate_limit` | 429 | The request limit is reached. `:quota` is always populated. |
| `:transport` | nil | A network failure, timeout, or non-JSON body. |
| `:demografix` | other | Any other non-2xx response. |

A batch of more than 10 names returns a `:validation` error before any request is sent.

```elixir
case Demografix.genderize_batch(client, names) do
  {:ok, batch} ->
    summarize(batch.results)

  {:error, %Demografix.Error{kind: :rate_limit, quota: quota}} ->
    # reset reports the seconds until the window resets.
    Process.sleep(quota.reset * 1_000)
    retry()

  {:error, error} ->
    {:error, Exception.message(error)}
end
```

The bang variants raise the same `Demografix.Error`, so `rescue` works against it.

## Methods

| Function | Returns | Notes |
|---|---|---|
| `Demografix.new(api_key, opts \\ [])` | `t()` | `opts`: `:timeout` (ms) |
| `genderize(client, name, opts \\ [])` | `{:ok, %Genderize{}}` | `opts`: `:country_id` |
| `genderize_batch(client, names, opts \\ [])` | `{:ok, %Batch{}}` | `opts`: `:country_id`; max 10 names |
| `agify(client, name, opts \\ [])` | `{:ok, %Agify{}}` | `opts`: `:country_id` |
| `agify_batch(client, names, opts \\ [])` | `{:ok, %Batch{}}` | `opts`: `:country_id`; max 10 names |
| `nationalize(client, name, opts \\ [])` | `{:ok, %Nationalize{}}` | no `country_id` |
| `nationalize_batch(client, names, opts \\ [])` | `{:ok, %Batch{}}` | max 10 names |

Each function has a bang variant (`genderize!/3`, `genderize_batch!/3`, and so on) that returns the result or raises `Demografix.Error`.

## Testing against the client

The base URLs are hardcoded constants, not options. To test without the network, set `plug: {Req.Test, Demografix}` and stub the response with the [Req testing](https://hexdocs.pm/req/Req.Test.html) tools:

```elixir
# config/test.exs
config :demografix, :req_options, plug: {Req.Test, Demografix}
```

```elixir
Req.Test.stub(Demografix, fn conn ->
  conn
  |> Plug.Conn.put_resp_header("x-rate-limit-remaining", "24987")
  |> Plug.Conn.put_resp_content_type("application/json")
  |> Plug.Conn.send_resp(200, ~s({"name": "peter", "gender": "male", "probability": 1.0, "count": 1}))
end)
```

## Reference

Full API reference: <https://genderize.io/documentation/api>. An API key is required. Creating one is free and includes 2,500 requests per month. Generate a key in your dashboard at [genderize.io](https://genderize.io), [agify.io](https://agify.io), or [nationalize.io](https://nationalize.io). One key works across all three services.
