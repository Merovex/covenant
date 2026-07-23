import { Controller } from "@hotwired/stimulus"
import "jsvectormap"
import "jsvectormap-world"

// Choropleth heat map of downloads by country (admin /downloads dashboard).
// data-value is { "US": 12, "DE": 3 } keyed by ISO country code.
//
// jsVectorMap's series scale is a categorical lookup (no numeric interpolation),
// so we quantize counts into STEPS buckets and hand it a bucket→color ramp we
// interpolate ourselves between the --geo-low/--geo-high theme colors (with
// hardcoded fallbacks). oklch()/color-mix() tokens are normalized to hex via a
// 1px canvas — jsVectorMap's color parser only understands hex.
export default class extends Controller {
  static values = { data: Object }

  connect() {
    const STEPS = 5
    const counts = this.dataValue
    const max = Math.max(...Object.values(counts), 1)
    const low = this.themeColor("--geo-low", "#d6e8df")
    const high = this.themeColor("--geo-high", "#1f6b4f")

    const scale = {}
    for (let step = 1; step <= STEPS; step++) {
      scale[step] = this.mixHex(low, high, STEPS === 1 ? 1 : (step - 1) / (STEPS - 1))
    }
    const buckets = {}
    for (const [ code, count ] of Object.entries(counts)) {
      buckets[code] = Math.max(1, Math.ceil((count / max) * STEPS))
    }

    this.map = new window.jsVectorMap({
      selector: `#${this.element.id}`,
      map: "world",
      zoomButtons: false,
      backgroundColor: "transparent",
      regionStyle: {
        initial: {
          fill: this.themeColor("--geo-nodata", "#e3e7e5"),
          stroke: this.themeColor("--geo-stroke", "#b7bdba"),
          strokeWidth: 0.3
        },
        hover: { fillOpacity: 0.8 }
      },
      series: { regions: [ { attribute: "fill", values: buckets, scale } ] },
      onRegionTooltipShow: (_event, tooltip, code) => {
        const count = counts[code]
        if (count) tooltip.text(`${tooltip.text()} — ${count} download${count === 1 ? "" : "s"}`)
      }
    })
  }

  disconnect() {
    this.map?.destroy()
    this.map = null
  }

  // Linear blend of two #rrggbb colors, t in 0..1.
  mixHex(from, to, t) {
    const parse = (hex) => [ 1, 3, 5 ].map((i) => parseInt(hex.slice(i, i + 2), 16))
    const [ r1, g1, b1 ] = parse(from)
    const [ r2, g2, b2 ] = parse(to)
    return "#" + [ r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t ]
      .map((channel) => Math.round(channel).toString(16).padStart(2, "0")).join("")
  }

  // Resolve a --geo-* token to plain #rrggbb by painting a pixel and reading it
  // back — the reliable way to normalize oklch()/color-mix() values to hex.
  themeColor(property, fallback) {
    const raw = getComputedStyle(this.element).getPropertyValue(property).trim()
    if (!raw) return fallback
    if (!this.constructor._colorContext) {
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = 1
      this.constructor._colorContext = canvas.getContext("2d", { willReadFrequently: true })
    }
    const context = this.constructor._colorContext
    context.fillStyle = fallback
    context.fillStyle = raw
    context.fillRect(0, 0, 1, 1)
    const [ r, g, b ] = context.getImageData(0, 0, 1, 1).data
    return "#" + [ r, g, b ].map((channel) => channel.toString(16).padStart(2, "0")).join("")
  }
}
