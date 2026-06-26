defmodule Demografix.Client do
  @moduledoc """
  Internal HTTP client for the Demografix APIs.

  Holds the `Demografix.new/2` struct and performs the single and batch requests.
  The public API in `Demografix` delegates here. Treat this module as internal;
  call through `Demografix` instead.

  ## Test seam

  Per-request options are merged from `Application.get_env(:demografix, :req_options, [])`,
  so tests set `plug: {Req.Test, Demografix}` without changing the hardcoded base
  URLs. See the README testing section.
  """

  alias Demografix.{
    Agify,
    AgifyPrediction,
    Batch,
    Error,
    Genderize,
    GenderizePrediction,
    Nationalize,
    NationalizeCountry,
    NationalizePrediction,
    Quota
  }

  @version Mix.Project.config()[:version] || "0.1.0"
  @user_agent "demografix-elixir/#{@version}"
  @max_batch 10

  @hosts %{
    genderize: "https://api.genderize.io",
    agify: "https://api.agify.io",
    nationalize: "https://api.nationalize.io"
  }

  @default_timeout 10_000

  @enforce_keys [:timeout, :api_key]
  defstruct [:timeout, :api_key]

  @type t :: %__MODULE__{api_key: String.t(), timeout: pos_integer()}

  @doc false
  @spec new(String.t(), keyword()) :: t()
  def new(api_key, opts \\ []) do
    validate_api_key(api_key)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    %__MODULE__{api_key: api_key, timeout: timeout}
  end

  defp validate_api_key(api_key) when is_binary(api_key) do
    if String.trim(api_key) == "" do
      raise ArgumentError, "api_key is required"
    end
  end

  defp validate_api_key(_api_key) do
    raise ArgumentError, "api_key is required"
  end

  @doc false
  @spec genderize(t(), String.t(), keyword()) :: {:ok, Genderize.t()} | {:error, Error.t()}
  def genderize(client, name, opts \\ []) do
    request_single(client, :genderize, name, opts, &decode_genderize/2)
  end

  @doc false
  @spec genderize_batch(t(), [String.t()], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  def genderize_batch(client, names, opts \\ []) do
    request_batch(client, :genderize, names, opts, &decode_genderize_prediction/1)
  end

  @doc false
  @spec agify(t(), String.t(), keyword()) :: {:ok, Agify.t()} | {:error, Error.t()}
  def agify(client, name, opts \\ []) do
    request_single(client, :agify, name, opts, &decode_agify/2)
  end

  @doc false
  @spec agify_batch(t(), [String.t()], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  def agify_batch(client, names, opts \\ []) do
    request_batch(client, :agify, names, opts, &decode_agify_prediction/1)
  end

  @doc false
  @spec nationalize(t(), String.t(), keyword()) :: {:ok, Nationalize.t()} | {:error, Error.t()}
  def nationalize(client, name, opts \\ []) do
    request_single(client, :nationalize, name, opts, &decode_nationalize/2)
  end

  @doc false
  @spec nationalize_batch(t(), [String.t()], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  def nationalize_batch(client, names, opts \\ []) do
    request_batch(client, :nationalize, names, opts, &decode_nationalize_prediction/1)
  end

  # --- request orchestration ---

  defp request_single(client, service, name, opts, decoder) do
    params = [{"name", name}] ++ country_param(service, opts) ++ apikey_param(client)

    with {:ok, body, quota} <- request(client, service, params) do
      decode_object(body, quota, decoder)
    end
  end

  defp request_batch(client, service, names, opts, decoder) do
    with :ok <- validate_batch_size(names),
         params = batch_params(client, service, names, opts),
         {:ok, body, quota} <- request(client, service, params) do
      decode_array(body, quota, decoder)
    end
  end

  defp batch_params(client, service, names, opts) do
    Enum.map(names, &{"name[]", &1}) ++ country_param(service, opts) ++ apikey_param(client)
  end

  defp validate_batch_size(names) when length(names) > @max_batch do
    {:error, Error.validation("Maximum #{@max_batch} names per batch request")}
  end

  defp validate_batch_size(_names), do: :ok

  defp country_param(service, opts) when service in [:genderize, :agify] do
    case Keyword.get(opts, :country_id) do
      nil -> []
      country_id -> [{"country_id", country_id}]
    end
  end

  defp country_param(_service, _opts), do: []

  defp apikey_param(%__MODULE__{api_key: api_key}), do: [{"apikey", api_key}]

  # --- HTTP ---

  defp request(client, service, params) do
    options =
      [
        url: @hosts[service],
        method: :get,
        params: params,
        headers: [{"user-agent", @user_agent}],
        receive_timeout: client.timeout,
        retry: false,
        # Keep the raw body so a non-JSON response (e.g. an HTML 502) can be
        # detected here rather than auto-decoded by Req. Per the contract, any
        # non-JSON body is a transport error regardless of status.
        decode_body: false
      ]
      |> Keyword.merge(Application.get_env(:demografix, :req_options, []))

    case Req.request(options) do
      {:ok, %Req.Response{status: status, headers: headers, body: body}} ->
        handle_response(status, headers, body)

      {:error, exception} ->
        {:error, Error.transport(Exception.message(exception))}
    end
  end

  # Parse the body as JSON FIRST, regardless of HTTP status. A non-JSON (or
  # empty) body is always a transport error per the contract, carrying the
  # status and the quota from the rate-limit headers when present. Only a
  # well-formed JSON body proceeds to status -> error mapping or success.
  defp handle_response(status, headers, body) do
    quota = parse_quota(headers)

    case decode_json(body) do
      {:ok, decoded} -> handle_json(status, decoded, quota)
      :error -> {:error, Error.transport("Non-JSON response body", status, quota)}
    end
  end

  defp handle_json(status, decoded, quota) when status in 200..299 do
    {:ok, decoded, quota}
  end

  defp handle_json(status, decoded, quota) do
    {:error, Error.from_status(status, error_message(decoded), quota)}
  end

  defp error_message(%{"error" => message}) when is_binary(message), do: message
  defp error_message(_decoded), do: "Request failed"

  # With `decode_body: false`, Req hands back the raw body as a binary, so decode
  # it here. A non-binary, empty, or invalid body is treated as non-JSON.
  defp decode_json(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> :error
    end
  end

  defp decode_json(_body), do: :error

  # --- decoding ---

  defp decode_object(body, quota, decoder) when is_map(body) do
    {:ok, decoder.(body, quota)}
  end

  defp decode_object(_body, _quota, _decoder) do
    {:error, Error.transport("Expected a JSON object")}
  end

  defp decode_array(body, quota, decoder) when is_list(body) do
    results = Enum.map(body, decoder)
    {:ok, %Batch{results: results, quota: quota}}
  end

  defp decode_array(_body, _quota, _decoder) do
    {:error, Error.transport("Expected a JSON array")}
  end

  defp decode_genderize(body, quota) do
    %Genderize{
      name: body["name"],
      gender: body["gender"],
      probability: body["probability"],
      count: body["count"],
      country_id: body["country_id"],
      quota: quota
    }
  end

  defp decode_genderize_prediction(body) do
    %GenderizePrediction{
      name: body["name"],
      gender: body["gender"],
      probability: body["probability"],
      count: body["count"],
      country_id: body["country_id"]
    }
  end

  defp decode_agify(body, quota) do
    %Agify{
      name: body["name"],
      age: body["age"],
      count: body["count"],
      country_id: body["country_id"],
      quota: quota
    }
  end

  defp decode_agify_prediction(body) do
    %AgifyPrediction{
      name: body["name"],
      age: body["age"],
      count: body["count"],
      country_id: body["country_id"]
    }
  end

  defp decode_nationalize(body, quota) do
    %Nationalize{
      name: body["name"],
      country: decode_countries(body["country"]),
      count: body["count"],
      quota: quota
    }
  end

  defp decode_nationalize_prediction(body) do
    %NationalizePrediction{
      name: body["name"],
      country: decode_countries(body["country"]),
      count: body["count"]
    }
  end

  defp decode_countries(nil), do: []

  defp decode_countries(countries) when is_list(countries) do
    Enum.map(countries, fn entry ->
      %NationalizeCountry{
        country_id: entry["country_id"],
        probability: entry["probability"]
      }
    end)
  end

  # --- headers ---

  defp parse_quota(headers) do
    %Quota{
      limit: header_int(headers, "x-rate-limit-limit"),
      remaining: header_int(headers, "x-rate-limit-remaining"),
      reset: header_int(headers, "x-rate-limit-reset")
    }
  end

  defp header_int(headers, name) do
    case header_value(headers, name) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {int, _rest} -> int
          :error -> nil
        end
    end
  end

  # Req normalizes headers to a map of lowercase keys to value lists, but accept
  # a list of tuples too. Match case-insensitively per the contract.
  defp header_value(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [value | _] -> value
      value when is_binary(value) -> value
      _ -> header_value(Enum.to_list(headers), name)
    end
  end

  defp header_value(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name do
        normalize_header_value(value)
      end
    end)
  end

  defp normalize_header_value([value | _]), do: value
  defp normalize_header_value(value) when is_binary(value), do: value
  defp normalize_header_value(_), do: nil
end
