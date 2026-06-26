# Summarize the gender, age, and nationality mix of a list of names.
#
# Run from the package root:
#
#     mix run examples/diversity_report.exs
#
# Set DEMOGRAFIX_API_KEY to a key from your dashboard at genderize.io, agify.io, or nationalize.io.

client = Demografix.new(System.fetch_env!("DEMOGRAFIX_API_KEY"))

names = ["peter", "lois", "kim", "michael", "nguyen"]

# Gender split across the list.
case Demografix.genderize_batch(client, names) do
  {:ok, batch} ->
    split = Enum.frequencies_by(batch.results, & &1.gender)
    IO.inspect(split, label: "gender split")
    IO.puts("quota remaining: #{batch.quota.remaining}")

  {:error, error} ->
    IO.puts("genderize failed: #{Exception.message(error)}")
end

# Age distribution across the list, ignoring names with no prediction.
case Demografix.agify_batch(client, names) do
  {:ok, batch} ->
    ages = batch.results |> Enum.map(& &1.age) |> Enum.reject(&is_nil/1)
    average = if ages == [], do: nil, else: Enum.sum(ages) / length(ages)
    IO.inspect(average, label: "average predicted age")

  {:error, error} ->
    IO.puts("agify failed: #{Exception.message(error)}")
end

# Nationality mix: tally the top country candidate for each name.
case Demografix.nationalize_batch(client, names) do
  {:ok, batch} ->
    mix =
      batch.results
      |> Enum.flat_map(fn prediction ->
        case prediction.country do
          [top | _] -> [top.country_id]
          [] -> []
        end
      end)
      |> Enum.frequencies()

    IO.inspect(mix, label: "top-country mix")

  {:error, error} ->
    IO.puts("nationalize failed: #{Exception.message(error)}")
end
