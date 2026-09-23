import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "image", "fallback" ]

  failed() {
    this.imageTarget.hidden = true
    this.fallbackTarget.hidden = false
  }
}
