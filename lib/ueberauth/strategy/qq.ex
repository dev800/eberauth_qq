defmodule Ueberauth.Strategy.QQ do
  @moduledoc """
  Provides an Ueberauth strategy for authenticating with QQ.

  ### Setup

  Include the provider in your configuration for Ueberauth

      config :ueberauth, Ueberauth,
        providers: [
          qq: { Ueberauth.Strategy.QQ, [] }
        ]

  Then include the configuration for qq.

      config :ueberauth, Ueberauth.Strategy.QQ.OAuth,
        client_id: System.get_env("QQ_APPID"),
        client_secret: System.get_env("QQ_SECRET")

  If you haven't already, create a pipeline and setup routes for your callback handler

      pipeline :auth do
        Ueberauth.plug "/auth"
      end

      scope "/auth" do
        pipe_through [:browser, :auth]

        get "/:provider/callback", AuthController, :callback
      end


  Create an endpoint for the callback where you will handle the `Ueberauth.Auth` struct

      defmodule MyApp.AuthController do
        use MyApp.Web, :controller

        def callback_phase(%{ assigns: %{ ueberauth_failure: fails } } = conn, _params) do
          # do things with the failure
        end

        def callback_phase(%{ assigns: %{ ueberauth_auth: auth } } = conn, params) do
          # do things with the auth
        end
      end

  """
  use Ueberauth.Strategy,
    uid_field: :uid,
    default_scope: "get_user_info",
    oauth2_module: Ueberauth.Strategy.QQ.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @user_info_url "https://graph.qq.com/user/get_user_info"

  def oauth2_module, do: Ueberauth.Strategy.QQ.OAuth

  def secure_random_hex(n \\ 16) do
    n
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Handles the initial redirect to the qq authentication page.

  To customize the scope (permissions) that are requested by qq include them as part of your url:

      "/auth/qq?scope=snsapi_userinfo"

  You can also include a `state` param that qq will return to you.
  """
  def handle_request!(conn) do
    conn = conn |> Plug.Conn.fetch_session()
    module = option(conn, :oauth2_module)
    scopes = conn.params["scope"] || option(conn, :default_scope)
    send_redirect_uri = Keyword.get(options(conn), :send_redirect_uri, true)
    config = conn.private[:ueberauth_request_options] |> Map.get(:options, [])
    redirect_uri = config[:redirect_uri] || callback_url(conn)
    state = secure_random_hex()

    params =
      if send_redirect_uri do
        [redirect_uri: redirect_uri, scope: scopes, state: state]
      else
        [scope: scopes, state: state]
      end

    conn
    |> Plug.Conn.put_session(:ueberauth_state, state)
    |> redirect!(apply(module, :authorize_url!, [params, [config: config]]))
  end

  @doc """
  Handles the callback from QQ. When there is a failure from QQ the failure is included in the
  `ueberauth_failure` struct. Otherwise the information returned from QQ is returned in the `Ueberauth.Auth` struct.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code, "state" => state}} = conn) do
    conn = conn |> Plug.Conn.fetch_session()
    module = option(conn, :oauth2_module)

    client_options =
      conn.private
      |> Map.get(:ueberauth_request_options, %{})
      |> Map.get(:options, [])

    options = [client_options: [config: client_options]]
    token = apply(module, :get_token!, [[code: code], [options: options]])
    session_state = conn |> Plug.Conn.get_session(:ueberauth_state)

    conn = conn |> Plug.Conn.delete_session(:ueberauth_state)

    cond do
      state != session_state ->
        set_errors!(conn, [
          error("StateMistake", "state misstake")
        ])

      token.access_token |> to_string |> String.length() == 0 ->
        set_errors!(conn, [
          error(token.other_params["error"], token.other_params["error_description"])
        ])

      true ->
        fetch_user(conn, token)
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection used for passing the raw QQ response around during the callback.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:qq_user, nil)
    |> put_private(:qq_token, nil)
  end

  @doc """
  Fetches the uid field from the QQ response. This defaults to the option `uid_field` which in-turn defaults to `id`
  """
  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string

    if conn.private[:qq_user] do
      conn.private.qq_user[uid_field]
    end
  end

  @doc """
  Includes the credentials from the QQ response.
  """
  def credentials(conn) do
    token = conn.private.qq_token
    scope_string = token.other_params["scope"] || ""
    scopes = String.split(scope_string, ",", trim: true)

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at,
      token_type: token.token_type,
      expires: !!token.expires_at,
      scopes: scopes
    }
  end

  def present?(str), do: str |> to_string() |> String.length() > 0

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.qq_user

    gender =
      case user["gender"] do
        "男" ->
          :male

        "女" ->
          :female

        "male" ->
          :male

        "female" ->
          :female

        _ ->
          :default
      end

    areas = [user["province"], user["city"]] |> Enum.filter(fn area -> present?(area) end)

    %Info{
      nickname: user["nickname"],
      image: user["figureurl_qq"],
      gender: gender,
      areas: areas
    }
  end

  @doc """
  Stores the raw information (including the token) obtained from the QQ callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.qq_token,
        user: conn.private.qq_user
      }
    }
  end

  def fetch_user(conn, token) do
    conn = put_private(conn, :qq_token, token)

    # Will be better with Elixir 1.3 with/else
    case Ueberauth.Strategy.QQ.OAuth.get(token, @user_info_url) do
      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %OAuth2.Response{status_code: _status_code, body: body}} ->
        put_private(conn, :qq_user, Jason.decode!(body))

      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn) || [], key, Keyword.get(default_options(), key))
  end
end
