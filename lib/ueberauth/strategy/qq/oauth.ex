defmodule Ueberauth.Strategy.QQ.OAuth do
  @moduledoc """
  An implementation of OAuth2 for qq.

  To add your `client_id` and `client_secret` include these values in your configuration.

      config :ueberauth, Ueberauth.Strategy.QQ.OAuth,
        client_id: System.get_env("QQ_APPID"),
        client_secret: System.get_env("QQ_SECRET")
  """
  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://graph.qq.com/oauth2.0/",
    authorize_url: "https://graph.qq.com/oauth2.0/authorize",
    token_url: "https://graph.qq.com/oauth2.0/token",
    refresh_token_url: "https://graph.qq.com/oauth2.0/token",
    id_url: "https://graph.qq.com/oauth2.0/me"
  ]

  @doc """
  Construct a client for requests to QQ.

  Optionally include any OAuth2 options here to be merged with the defaults.

      Ueberauth.Strategy.QQ.OAuth.client(redirect_uri: "http://localhost:4000/auth/qq/callback")

  This will be setup automatically for you in `Ueberauth.Strategy.QQ`.
  These options are only useful for usage outside the normal callback phase of Ueberauth.
  """
  def client(opts \\ []) do
    config =
      :ueberauth
      |> Application.fetch_env!(Ueberauth.Strategy.QQ.OAuth)
      |> check_config_key_exists(:client_id)
      |> check_config_key_exists(:client_secret)

    client_opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    OAuth2.Client.new(client_opts)
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth. No need to call this usually.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client
    |> OAuth2.Client.authorize_url!(params)
  end

  def get(token, url, _headers \\ [], _opts \\ []) do
    token.access_token
    |> _get_uid()
    |> case do
      {:ok, uid} ->
        uid |> _get_user_info(token.access_token, url)

      {:error, error_reason} ->
        {:error, %OAuth2.Error{reason: error_reason}}
    end
  end

  defp _get_user_info(uid, access_token, url) do
    client = [token: access_token] |> client()

    params = %{
      format: "json",
      openid: uid,
      oauth_consumer_key: client.client_id,
      access_token: access_token
    }

    case HTTPoison.get("#{url}?#{URI.encode_query(params)}") do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        body
        |> Jason.decode!()
        |> case do
          %{"ret" => 0} = user ->
            body = user |> Map.put("uid", uid) |> Jason.encode!()
            {:ok, %OAuth2.Response{status_code: 200, body: body}}

          %{"msg" => error_description} ->
            {:error, %OAuth2.Error{reason: error_description}}

          _ ->
            {:error, %OAuth2.Error{reason: "get user info fail"}}
        end

      _ ->
        {:error, %OAuth2.Error{reason: "get user info fail"}}
    end
  end

  defp _get_uid(nil), do: {:error, "token is nil"}

  defp _get_uid(access_token) do
    params = %{access_token: access_token}

    case HTTPoison.get("#{@defaults[:id_url]}?#{URI.encode_query(params)}") do
      {:ok, %HTTPoison.Response{body: response_body, status_code: 200}} ->
        case response_body |> normalize_response_body do
          %{"client_id" => _client_id, "openid" => uid} ->
            {:ok, uid}

          %{"error" => _error_code, "error_description" => error_description} ->
            {:error, error_description}

          %{"code" => _code, "msg" => error_description} ->
            {:error, error_description}
        end

      {:error, error_reason} ->
        {:error, error_reason}
    end
  end

  def get_token!(params \\ [], options \\ []) do
    headers = Keyword.get(options, :headers, [])
    options = Keyword.get(options, :options, [])
    client_options = Keyword.get(options, :client_options, [])
    oauth_client = client(client_options)

    params =
      params
      |> Keyword.put(:grant_type, "authorization_code")
      |> Keyword.put(:client_id, oauth_client.client_id)
      |> Keyword.put(:client_secret, oauth_client.client_secret)

    token_url =
      "#{oauth_client.token_url}?#{
        URI.encode_query(%{
          grant_type: "authorization_code",
          client_id: oauth_client.client_id,
          client_secret: oauth_client.client_secret,
          code: params[:code],
          redirect_uri: oauth_client.redirect_uri
        })
      }"

    token_url
    |> HTTPoison.get(headers)
    |> _parse_access_token(params)
  end

  def refresh_token!(refresh_token, options \\ []) do
    headers = Keyword.get(options, :headers, [])
    options = Keyword.get(options, :options, [])
    client = Keyword.get(options, :client_options, []) |> client()

    url =
      "#{@defaults[:refresh_token_url]}?#{
        URI.encode_query(%{
          client_id: client.client_id,
          client_secret: client.client_secret,
          grant_type: "refresh_token",
          refresh_token: refresh_token
        })
      }"

    url
    |> HTTPoison.get(headers)
    |> _parse_access_token()
  end

  defp _parse_access_token(response, params \\ []) do
    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        if String.starts_with?(body, ["callback( {"]) do
          %OAuth2.AccessToken{
            other_params: body |> normalize_response_body
          }
        else
          token =
            body
            |> URI.decode_query()
            |> Jason.encode!()
            |> Jason.decode!(keys: :atoms)

          expires_at = Timex.now() |> Timex.shift(seconds: String.to_integer(token.expires_in))

          %OAuth2.AccessToken{
            other_params: params |> Map.new(),
            token_type: "Bearer",
            expires_at: expires_at,
            refresh_token: token[:refresh_token],
            access_token: token[:access_token]
          }
        end

      _ ->
        %OAuth2.AccessToken{
          other_params: %{"error" => "fail", "error_description" => "access_token fetch fail"}
        }
    end
  end

  def normalize_response_body(body) do
    body
    |> String.slice(10, String.length(body) - 14)
    |> Jason.decode!()
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    client
    |> put_param(:response_type, "code")
    |> put_param(:appid, client.client_id)
    |> put_param(:redirect_uri, client.redirect_uri)
    |> OAuth2.Strategy.AuthCode.authorize_url(params)
  end

  def get_token(client, params, headers) do
    {code, params} = Keyword.pop(params, :code, client.params["code"])

    unless code do
      raise OAuth2.Error, reason: "Missing required key `code` for `#{inspect(__MODULE__)}`"
    end

    client
    |> put_param(:appid, client.client_id)
    |> put_param(:code, code)
    |> put_param(:secret, client.client_secret)
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end

  defp check_config_key_exists(config, key) when is_list(config) do
    unless Keyword.has_key?(config, key) do
      raise "#{inspect(key)} missing from config :ueberauth, Ueberauth.Strategy.QQ"
    end

    config
  end

  defp check_config_key_exists(_, _) do
    raise "Config :ueberauth, Ueberauth.Strategy.QQ is not a keyword list, as expected"
  end
end
