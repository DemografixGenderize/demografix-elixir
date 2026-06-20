defmodule Demografix.Quota do
  @moduledoc """
  The rate-limit state read from the `x-rate-limit-*` response headers.

  Present on every successful result and on every error raised after a response.
  The values reflect the response that produced them; quota is never cached on
  the client.
  """

  @enforce_keys [:limit, :remaining, :reset]
  defstruct [:limit, :remaining, :reset]

  @type t :: %__MODULE__{
          limit: integer() | nil,
          remaining: integer() | nil,
          reset: integer() | nil
        }
end

defmodule Demografix.Genderize do
  @moduledoc """
  A single genderize result: the prediction fields plus the response `:quota`.

  `:gender` is `"male"`, `"female"`, or `nil`. `:country_id` is set only when the
  request sent a `country_id`.
  """

  @enforce_keys [:name, :gender, :probability, :count, :quota]
  defstruct [:name, :gender, :probability, :count, :country_id, :quota]

  @type t :: %__MODULE__{
          name: String.t(),
          gender: String.t() | nil,
          probability: float(),
          count: integer(),
          country_id: String.t() | nil,
          quota: Demografix.Quota.t()
        }
end

defmodule Demografix.GenderizePrediction do
  @moduledoc """
  One genderize prediction inside a batch result. Carries no quota of its own;
  the batch holds one quota for the whole response.
  """

  @enforce_keys [:name, :gender, :probability, :count]
  defstruct [:name, :gender, :probability, :count, :country_id]

  @type t :: %__MODULE__{
          name: String.t(),
          gender: String.t() | nil,
          probability: float(),
          count: integer(),
          country_id: String.t() | nil
        }
end

defmodule Demografix.Agify do
  @moduledoc """
  A single agify result: the prediction fields plus the response `:quota`.

  `:age` is an integer or `nil`. `:country_id` is set only when the request sent
  a `country_id`.
  """

  @enforce_keys [:name, :age, :count, :quota]
  defstruct [:name, :age, :count, :country_id, :quota]

  @type t :: %__MODULE__{
          name: String.t(),
          age: integer() | nil,
          count: integer(),
          country_id: String.t() | nil,
          quota: Demografix.Quota.t()
        }
end

defmodule Demografix.AgifyPrediction do
  @moduledoc """
  One agify prediction inside a batch result. Carries no quota of its own.
  """

  @enforce_keys [:name, :age, :count]
  defstruct [:name, :age, :count, :country_id]

  @type t :: %__MODULE__{
          name: String.t(),
          age: integer() | nil,
          count: integer(),
          country_id: String.t() | nil
        }
end

defmodule Demografix.NationalizeCountry do
  @moduledoc """
  One country candidate in a nationalize prediction.
  """

  @enforce_keys [:country_id, :probability]
  defstruct [:country_id, :probability]

  @type t :: %__MODULE__{
          country_id: String.t(),
          probability: float()
        }
end

defmodule Demografix.Nationalize do
  @moduledoc """
  A single nationalize result: the prediction fields plus the response `:quota`.

  `:country` is a list of up to five `Demografix.NationalizeCountry` candidates in
  descending probability, empty when there is no match.
  """

  @enforce_keys [:name, :country, :count, :quota]
  defstruct [:name, :country, :count, :quota]

  @type t :: %__MODULE__{
          name: String.t(),
          country: [Demografix.NationalizeCountry.t()],
          count: integer(),
          quota: Demografix.Quota.t()
        }
end

defmodule Demografix.NationalizePrediction do
  @moduledoc """
  One nationalize prediction inside a batch result. Carries no quota of its own.
  """

  @enforce_keys [:name, :country, :count]
  defstruct [:name, :country, :count]

  @type t :: %__MODULE__{
          name: String.t(),
          country: [Demografix.NationalizeCountry.t()],
          count: integer()
        }
end

defmodule Demografix.Batch do
  @moduledoc """
  A batch result: the per-name `:results` list in input order plus one `:quota`
  for the whole response.
  """

  @enforce_keys [:results, :quota]
  defstruct [:results, :quota]

  @type t :: %__MODULE__{
          results: [
            Demografix.GenderizePrediction.t()
            | Demografix.AgifyPrediction.t()
            | Demografix.NationalizePrediction.t()
          ],
          quota: Demografix.Quota.t()
        }
end
