let renderer = null

async function getRenderer() {
  if (!renderer) {
    renderer = await import("zpl-renderer-js")
  }
  return renderer
}

function parseSizeMm(size) {
  const [w, h] = (size || "4x6").split("x").map(Number)
  return [w * 25.4, h * 25.4]
}

function parseDpmm(dpmm) {
  return parseInt(dpmm) || 8
}

const ZplPreview = {
  async mounted() {
    await this.render()
  },
  async updated() {
    await this.render()
  },
  async render() {
    const zpl = this.el.dataset.zpl
    if (!zpl) return

    const [widthMm, heightMm] = parseSizeMm(this.el.dataset.size)
    const dpmm = parseDpmm(this.el.dataset.dpmm)

    this.el.innerHTML = '<span class="preview-loading">Rendering…</span>'

    try {
      const { zplToBase64MultipleAsync } = await getRenderer()
      const pages = await zplToBase64MultipleAsync(zpl, widthMm, heightMm, dpmm)
      const total = pages.length
      this.el.innerHTML = pages
        .map((b64, i) => {
          const label = total > 1 ? `<span class="preview-page-label">${i + 1} / ${total}</span>` : ""
          return `<div class="preview-page">${label}<img src="data:image/png;base64,${b64}" alt="Label ${i + 1}" /></div>`
        })
        .join("")
    } catch (e) {
      console.error("ZPL render failed:", e)
      this.el.innerHTML = '<span class="preview-error">Preview unavailable</span>'
    }
  }
}

export default ZplPreview
