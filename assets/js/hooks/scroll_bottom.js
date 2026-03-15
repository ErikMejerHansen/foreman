const ScrollBottomHook = {
  mounted() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.maybeScrollToBottom())
    this.observer.observe(this.el, { childList: true, subtree: true })
    this.el.addEventListener("scroll", () => this.onScroll())
  },

  updated() {
    this.maybeScrollToBottom()
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  onScroll() {
    const el = this.el
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 50
    this.userScrolledUp = !atBottom
  },

  maybeScrollToBottom() {
    if (!this.userScrolledUp) {
      this.scrollToBottom()
    }
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

export default ScrollBottomHook
