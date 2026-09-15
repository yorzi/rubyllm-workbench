import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  start() {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = true
    this.submitTarget.dataset.originalLabel = this.submitTarget.value
    this.submitTarget.value = "Queueing…"
  }

  finish() {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = false
    this.submitTarget.value = this.submitTarget.dataset.originalLabel || "Run"
  }
}
