defmodule ManaChessOnlineWeb.AdminLiveTest do
  use ManaChessOnlineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    previous_password = System.get_env("ADMIN_PASSWORD")
    System.put_env("ADMIN_PASSWORD", "test-admin-password")

    on_exit(fn ->
      if previous_password do
        System.put_env("ADMIN_PASSWORD", previous_password)
      else
        System.delete_env("ADMIN_PASSWORD")
      end
    end)

    :ok
  end

  test "login form signals when it is ready and accepts the configured password", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(
             view,
             "form.mc-admin-login input#admin-password[required][aria-invalid='false']"
           )

    assert has_element?(
             view,
             "form.mc-admin-login button.mc-admin-login-submit[phx-disable-with='Entrando...']"
           )

    view
    |> form("form.mc-admin-login", password: "test-admin-password")
    |> render_submit()

    assert has_element?(view, "form[phx-submit='save_settings']")
    refute has_element?(view, "form.mc-admin-login")
  end

  test "login rejects a wrong password", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    html =
      view
      |> form("form.mc-admin-login", password: "wrong-password")
      |> render_submit()

    assert html =~ "Clave incorrecta."
    assert has_element?(view, "#admin-password[aria-invalid='true'][aria-describedby='admin-login-error']")
    assert has_element?(view, "#admin-login-error[role='alert']", "Clave incorrecta.")
    assert has_element?(view, "form.mc-admin-login")
  end

  test "login fails closed when ADMIN_PASSWORD is missing", %{conn: conn} do
    System.delete_env("ADMIN_PASSWORD")
    {:ok, view, _html} = live(conn, ~p"/admin")

    html =
      view
      |> form("form.mc-admin-login", password: "mana")
      |> render_submit()

    assert html =~ "Clave incorrecta."
    assert has_element?(view, "form.mc-admin-login")
  end
end
