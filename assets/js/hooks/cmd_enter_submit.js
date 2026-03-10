const CmdEnterSubmitHook = {
  mounted() {
    this.handler = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault()
        this.el.requestSubmit()
      }
    }
    this.el.addEventListener("keydown", this.handler)
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.handler)
  }
}

export default CmdEnterSubmitHook
