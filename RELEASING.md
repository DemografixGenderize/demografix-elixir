# Releasing

This package publishes to [Hex](https://hex.pm) as `demografix`. Continuous
integration runs on every push to `main` and on pull requests. Releases are cut
by pushing a `vX.Y.Z` git tag, which runs `.github/workflows/release.yml`.

## One-time setup

Hex does not support OIDC trusted publishing, so a publish-scoped API key is
required.

1. Create a Hex account and confirm you are an owner of the `demografix`
   package (`mix hex.user register`, then `mix hex.owner add demografix <email>`
   from an existing owner).
2. Generate a publish-scoped API key:

   ```sh
   mix hex.user key generate --key-name demografix-ci --permission api:write
   ```

3. Add the key as a repository secret named `HEX_API_KEY`:
   GitHub repo -> Settings -> Secrets and variables -> Actions -> New
   repository secret. Name it `HEX_API_KEY` and paste the generated key.

The release workflow reads the key from `${{ secrets.HEX_API_KEY }}`. The key is
never stored in the repository.

## Cutting a release

1. Bump `@version` in `mix.exs` to the new `X.Y.Z`.
2. Commit the bump:

   ```sh
   git commit -am "Release vX.Y.Z"
   ```

3. Tag and push the tag:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

The release job verifies that the tag version matches `@version` in `mix.exs`,
runs `mix deps.get`, publishes with `mix hex.publish --yes`, and creates a
GitHub Release. If the tag and manifest versions disagree, the job fails before
publishing.

## Consuming the package

Add the dependency to `mix.exs`:

```elixir
{:demografix, "~> X.Y"}
```
