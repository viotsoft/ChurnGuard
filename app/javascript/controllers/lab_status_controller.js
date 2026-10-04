import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.timer = window.setInterval(() => this.poll(), 2500)
  }

  disconnect() {
    window.clearInterval(this.timer)
  }

  async poll() {
    const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    if (!response.ok) return

    const state = await response.json()
    if (state.redirect_url) window.location.assign(state.redirect_url)
  }
}
