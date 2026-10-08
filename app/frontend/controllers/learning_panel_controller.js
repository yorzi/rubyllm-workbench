import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reveal() {
    const topic = this.element.querySelector("[data-learning-topic]")
    if (!topic || !window.matchMedia("(max-width: 1023px)").matches) return

    topic.scrollIntoView({ behavior: "instant", block: "start" })
    topic.focus({ preventScroll: true })
  }
}
