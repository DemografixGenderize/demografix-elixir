defmodule Demografix.Error do
  @moduledoc """
  The error returned or raised by every Demografix call.

  A single struct carries the typed `:kind`, the HTTP `:status`, the server
  `:message`, and the `:quota` parsed from the rate-limit headers when present.

  ## Kinds

  | `:kind`            | Status | Meaning                                                       |
  |--------------------|--------|---------------------------------------------------------------|
  | `:auth`            | 401    | Invalid API key.                                              |
  | `:subscription`    | 402    | Freebie expired or subscription is not active.                |
  | `:validation`      | 422    | Invalid parameters; also raised client-side for >10 names.    |
  | `:rate_limit`      | 429    | Request limit reached. `:quota` is always populated.          |
  | `:transport`       | nil    | Network failure, timeout, or a non-JSON body.                 |
  | `:demografix`      | other  | Any other non-2xx response.                                   |

  Match on `:kind` to branch on the error type.
  """

  defexception [:kind, :status, :message, :quota]

  @type kind ::
          :auth
          | :subscription
          | :validation
          | :rate_limit
          | :transport
          | :demografix

  @type t :: %__MODULE__{
          kind: kind(),
          status: integer() | nil,
          message: String.t(),
          quota: Demografix.Quota.t() | nil
        }

  @impl true
  def message(%__MODULE__{status: nil, message: message}), do: message
  def message(%__MODULE__{status: status, message: message}), do: "#{status}: #{message}"

  @doc false
  @spec from_status(integer(), String.t(), Demografix.Quota.t() | nil) :: t()
  def from_status(status, message, quota) do
    %__MODULE__{kind: kind_for(status), status: status, message: message, quota: quota}
  end

  @doc false
  @spec transport(String.t(), integer() | nil, Demografix.Quota.t() | nil) :: t()
  def transport(message, status \\ nil, quota \\ nil) do
    %__MODULE__{kind: :transport, status: status, message: message, quota: quota}
  end

  @doc false
  @spec validation(String.t()) :: t()
  def validation(message) do
    %__MODULE__{kind: :validation, status: nil, message: message, quota: nil}
  end

  defp kind_for(401), do: :auth
  defp kind_for(402), do: :subscription
  defp kind_for(422), do: :validation
  defp kind_for(429), do: :rate_limit
  defp kind_for(_), do: :demografix
end
