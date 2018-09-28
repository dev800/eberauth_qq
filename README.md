# Überauth QQ

> QQ OAuth2 strategy for Überauth.

## Installation

1. Add `:ueberauth_qq` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:ueberauth_qq, "git@github.com:dev800/ueberauth_qq.git"}]
    end
    ```

1. Add the strategy to your applications:

    ```elixir
    def application do
      [applications: [:ueberauth_qq]]
    end
    ```

1. Add QQ to your Überauth configuration:

    ```elixir
    config :ueberauth, Ueberauth,
      providers: [
        qq: {Ueberauth.Strategy.QQ, []}
      ]
    ```

1.  Update your provider configuration:

    ```elixir
    config :ueberauth, Ueberauth.Strategy.QQ.OAuth,
      client_id: System.get_env("QQ_APPID"),
      client_secret: System.get_env("QQ_SECRET")
    ```

1.  Include the Überauth plug in your controller:

    ```elixir
    defmodule MyApp.AuthController do
      use MyApp.Web, :controller

      pipeline :browser do
        plug Ueberauth
        ...
       end
    end
    ```

1.  Create the request and callback routes if you haven't already:

    ```elixir
    scope "/auth", MyApp do
      pipe_through :browser

      get "/:provider", AuthController, :request
      get "/:provider/callback", AuthController, :callback
    end
    ```

1. You controller needs to implement callbacks to deal with `Ueberauth.Auth` and `Ueberauth.Failure` responses.

For an example implementation see the [Überauth Example](https://github.com/ueberauth/ueberauth_example) application.

## Calling

Depending on the configured url you can initial the request through:

    /auth/qq

Or with options:

    /auth/qq?scope=snsapi_userinfo

