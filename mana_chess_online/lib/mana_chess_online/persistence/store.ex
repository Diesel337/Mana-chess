defmodule ManaChessOnline.Persistence.Store do
  @moduledoc false

  @callback persist(term()) :: :ok | {:ok, term()} | {:error, term()}
  @callback get_setting(String.t()) :: {:ok, map()} | {:error, term()}
  @callback entitlements_for(String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback competitive_profile(String.t()) :: {:ok, map()} | {:error, term()}
  @callback health() :: :ok | {:error, term()}
end
