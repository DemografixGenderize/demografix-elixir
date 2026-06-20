defmodule DemografixTest do
  use ExUnit.Case, async: true

  alias Demografix.{
    Agify,
    AgifyPrediction,
    Batch,
    Error,
    Genderize,
    Nationalize,
    NationalizeCountry,
    Quota
  }

  @headers [
    {"x-rate-limit-limit", "25000"},
    {"x-rate-limit-remaining", "24987"},
    {"x-rate-limit-reset", "1314000"}
  ]

  setup do
    {:ok, client: Demografix.new()}
  end

  # Stub the transport with a fixed status, the rate-limit headers, and a body.
  defp stub(status, body) do
    Req.Test.stub(Demografix, fn conn ->
      conn =
        Enum.reduce(@headers, conn, fn {name, value}, conn ->
          Plug.Conn.put_resp_header(conn, name, value)
        end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  # Capture the request so assertions can inspect the query string.
  defp capture_request(status, body) do
    test_pid = self()

    Req.Test.stub(Demografix, fn conn ->
      send(test_pid, {:request, conn.host, conn.query_string, Plug.Conn.get_req_header(conn, "user-agent")})

      conn =
        Enum.reduce(@headers, conn, fn {name, value}, conn ->
          Plug.Conn.put_resp_header(conn, name, value)
        end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  # --- 1. single parse + quota.remaining == 24987 ---

  test "genderize single parses fields and quota", %{client: client} do
    stub(200, ~s({"count": 1352696, "name": "peter", "gender": "male", "probability": 1.0}))

    assert {:ok, %Genderize{} = result} = Demografix.genderize(client, "peter")
    assert result.name == "peter"
    assert result.gender == "male"
    assert result.probability == 1.0
    assert result.count == 1_352_696
    assert result.country_id == nil
    assert %Quota{limit: 25000, remaining: 24987, reset: 1_314_000} = result.quota
  end

  test "agify single parses fields and quota", %{client: client} do
    stub(200, ~s({"name": "michael", "age": 57, "count": 311558}))

    assert {:ok, %Agify{} = result} = Demografix.agify(client, "michael")
    assert result.name == "michael"
    assert result.age == 57
    assert result.count == 311_558
    assert result.quota.remaining == 24987
  end

  test "nationalize single parses fields and quota", %{client: client} do
    stub(
      200,
      ~s({"count": 100783, "name": "nguyen", "country": [{"country_id": "VN", "probability": 0.891132}, {"country_id": "MO", "probability": 0.019031}]})
    )

    assert {:ok, %Nationalize{} = result} = Demografix.nationalize(client, "nguyen")
    assert result.name == "nguyen"
    assert result.count == 100_783
    assert [%NationalizeCountry{country_id: "VN", probability: 0.891132}, %NationalizeCountry{country_id: "MO"}] = result.country
    assert result.quota.remaining == 24987
  end

  # --- 2. batch parses results in order + quota ---

  test "agify batch parses results in input order with one quota", %{client: client} do
    stub(
      200,
      ~s([{"count": 311558, "name": "michael", "age": 57}, {"count": 55682, "name": "matthew", "age": 48}])
    )

    assert {:ok, %Batch{results: results, quota: quota}} =
             Demografix.agify_batch(client, ["michael", "matthew"])

    assert [%AgifyPrediction{name: "michael", age: 57}, %AgifyPrediction{name: "matthew", age: 48}] =
             results

    assert quota.remaining == 24987
  end

  test "batch query repeats name[] in order", %{client: client} do
    capture_request(200, ~s([{"name": "michael", "age": 57, "count": 1}, {"name": "matthew", "age": 48, "count": 1}]))

    assert {:ok, %Batch{}} = Demografix.agify_batch(client, ["michael", "matthew"])

    assert_receive {:request, "api.agify.io", query, ["demografix-elixir/0.1.0"]}
    # name[] is percent-encoded to name%5B%5D and repeated once per name in order.
    decoded_query = URI.decode(query)
    assert decoded_query =~ "name[]=michael"
    assert decoded_query =~ "name[]=matthew"

    assert :binary.match(decoded_query, "name[]=michael") <
             :binary.match(decoded_query, "name[]=matthew")

    refute query =~ "apikey"
  end

  # --- 3. null prediction returns null/empty without error ---

  test "genderize null prediction is a normal result", %{client: client} do
    stub(200, ~s({"name": "xÿz", "gender": null, "probability": 0.0, "count": 0}))

    assert {:ok, %Genderize{gender: nil, probability: +0.0, count: 0}} =
             Demografix.genderize(client, "xÿz")
  end

  test "agify null prediction is a normal result", %{client: client} do
    stub(200, ~s({"name": "xÿz", "age": null, "count": 0}))

    assert {:ok, %Agify{age: nil, count: 0}} = Demografix.agify(client, "xÿz")
  end

  test "nationalize null prediction returns an empty country list", %{client: client} do
    stub(200, ~s({"name": "xÿz", "country": [], "count": 0}))

    assert {:ok, %Nationalize{country: [], count: 0}} = Demografix.nationalize(client, "xÿz")
  end

  # --- 4. country_id round-trips into the request and back ---

  test "country_id is sent on the request and parsed from the response", %{client: client} do
    capture_request(
      200,
      ~s({"count": 196601, "name": "kim", "gender": "female", "country_id": "US", "probability": 0.94})
    )

    assert {:ok, %Genderize{country_id: "US"}} =
             Demografix.genderize(client, "kim", country_id: "US")

    assert_receive {:request, "api.genderize.io", query, _ua}
    assert URI.decode_query(query)["country_id"] == "US"
    assert URI.decode_query(query)["name"] == "kim"
  end

  # --- 5. batch of 11 names raises ValidationError with no HTTP call ---

  test "a batch of 11 names is rejected client-side with no request", %{client: client} do
    Req.Test.stub(Demografix, fn _conn ->
      flunk("no HTTP request must be made for an oversized batch")
    end)

    names = Enum.map(1..11, &"name#{&1}")

    assert {:error, %Error{kind: :validation, status: nil}} =
             Demografix.genderize_batch(client, names)
  end

  test "the bang batch variant raises for 11 names with no request", %{client: client} do
    Req.Test.stub(Demografix, fn _conn ->
      flunk("no HTTP request must be made for an oversized batch")
    end)

    names = Enum.map(1..11, &"name#{&1}")

    assert_raise Error, fn -> Demografix.genderize_batch!(client, names) end
  end

  # --- 6. status codes map to the right error kinds ---

  test "401 maps to an auth error carrying status and message", %{client: client} do
    stub(401, ~s({"error": "Invalid API key"}))

    assert {:error, %Error{kind: :auth, status: 401, message: "Invalid API key"}} =
             Demografix.genderize(client, "peter")
  end

  test "402 maps to a subscription error", %{client: client} do
    stub(402, ~s({"error": "Subscription is not active"}))

    assert {:error, %Error{kind: :subscription, status: 402, message: "Subscription is not active"}} =
             Demografix.agify(client, "peter")
  end

  test "422 maps to a validation error", %{client: client} do
    stub(422, ~s({"error": "Missing 'name' parameter"}))

    assert {:error, %Error{kind: :validation, status: 422, message: "Missing 'name' parameter"}} =
             Demografix.nationalize(client, "")
  end

  test "429 maps to a rate-limit error carrying quota", %{client: client} do
    stub(429, ~s({"error": "Request limit reached"}))

    assert {:error, %Error{kind: :rate_limit, status: 429, message: "Request limit reached"} = error} =
             Demografix.genderize(client, "peter")

    assert %Quota{limit: 25000, remaining: 24987, reset: 1_314_000} = error.quota
  end

  # --- extras: apikey, bang success, transport ---

  test "apikey is added to the query when the client has a key" do
    client = Demografix.new("secret-key")
    capture_request(200, ~s({"name": "peter", "gender": "male", "probability": 1.0, "count": 1}))

    assert {:ok, _} = Demografix.genderize(client, "peter")
    assert_receive {:request, _host, query, _ua}
    assert URI.decode_query(query)["apikey"] == "secret-key"
  end

  test "the bang variant returns the result on success", %{client: client} do
    stub(200, ~s({"name": "peter", "gender": "male", "probability": 1.0, "count": 1}))

    assert %Genderize{name: "peter"} = Demografix.genderize!(client, "peter")
  end

  test "a transport failure maps to a transport error", %{client: client} do
    Req.Test.stub(Demografix, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert {:error, %Error{kind: :transport, status: nil}} = Demografix.genderize(client, "peter")
  end

  test "non-JSON error body maps to transport error", %{client: client} do
    Req.Test.stub(Demografix, fn conn ->
      conn =
        Enum.reduce(@headers, conn, fn {name, value}, conn ->
          Plug.Conn.put_resp_header(conn, name, value)
        end)

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(502, "<html>502</html>")
    end)

    assert {:error, %Error{kind: :transport, status: 502} = error} =
             Demografix.genderize(client, "peter")

    assert error.quota.remaining == 24987
  end
end
