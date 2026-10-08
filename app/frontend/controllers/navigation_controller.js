import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "toggle"]

  toggle() {
    const collapsed = this.menuTarget.classList.toggle("hidden")
    this.toggleTarget.setAttribute("aria-expanded", String(!collapsed))
  }
}
