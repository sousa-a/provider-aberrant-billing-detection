"""
P3 - Provider Aberrant Billing Pattern Detection
visual_identity.py - Visual identity for all notebooks and figures.

Provides colors, matplotlib rcParams, and helper functions for consistent,
publication-quality charts across all P3 deliverables.

Usage:
    from src.visual_identity import *
"""

import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.ticker as mticker
from matplotlib.patches import Rectangle
import textwrap

from .config import DATA_SOURCE_CITATION

# =============================================================================
# Color palette
# =============================================================================

ECON_BG      = "#EDE5D8"
ECON_RED     = "#E3120B"
NATURE_TEAL  = "#009B8D"
NATURE_CORAL = "#E64B35"
DEEP_BLUE    = "#2B5E8C"
AMBER        = "#E8A33D"
PLUM         = "#7E4E90"
WARM_GREY    = "#8C8279"
CHARCOAL     = "#2D2926"
LIGHT_GREY   = "#D4CEC5"
PALE_TEAL    = "#E0F0EE"
PALE_RED     = "#FBEAE8"
WHITE        = "#FFFFFF"

PALETA_SEQ = [NATURE_TEAL, NATURE_CORAL, DEEP_BLUE, AMBER, PLUM, WARM_GREY]

# =============================================================================
# Font detection
# =============================================================================

_disp = [f.name for f in fm.fontManager.ttflist]
SERIF = next((f for f in ["Georgia", "Liberation Serif", "DejaVu Serif"]
              if f in _disp), "serif")
SANS  = next((f for f in ["Calibri", "Arial", "Liberation Sans", "DejaVu Sans"]
              if f in _disp), "sans-serif")

# =============================================================================
# Matplotlib rcParams
# =============================================================================

plt.rcParams.update({
    "figure.facecolor":   WHITE,
    "axes.facecolor":     ECON_BG,
    "savefig.facecolor":  WHITE,
    "font.family":        SANS,
    "font.size":          10,
    "text.color":         CHARCOAL,
    "axes.labelcolor":    CHARCOAL,
    "axes.edgecolor":     WARM_GREY,
    "axes.linewidth":     0.8,
    "axes.spines.top":    False,
    "axes.spines.right":  False,
    "xtick.color":        CHARCOAL,
    "ytick.color":        CHARCOAL,
    "xtick.major.size":   0,
    "ytick.major.size":   0,
    "xtick.labelsize":    9,
    "ytick.labelsize":    9,
    "axes.grid":          True,
    "axes.grid.axis":     "y",
    "grid.color":         WARM_GREY,
    "grid.linestyle":     ":",
    "grid.linewidth":     0.6,
    "grid.alpha":         0.5,
    "legend.frameon":     False,
    "legend.fontsize":    9,
    # Prevent the default ScalarFormatter from ever showing a bare
    # scientific-notation offset (e.g. "1e7") in the corner of an axis.
    # Large-magnitude axes should instead go through auto_scale_axis()
    # for clean, labeled K/M formatting.
    "axes.formatter.useoffset": False,
    "axes.formatter.limits":    (-5, 8),
    "figure.dpi":         110,
    "savefig.dpi":        300,
    "savefig.bbox":       "tight",
})

# =============================================================================
# Title positioning constants
# =============================================================================

_TITLE_Y = 0.965
_SUBTIT_Y = 0.93

# =============================================================================
# Helper functions
# =============================================================================

def _get_leftmost_x(fig) -> float:
    """
    Calculates the exact left-most figure-coordinate fraction of the entire figure,
    accounting for the width of y-axis labels and tick labels across ALL subplots.
    
    This approach guarantees maximum accuracy by evaluating every axis in the figure
    to find the absolute global minimum x-coordinate, preventing misalignment 
    in multi-column grid specifications.
    
    Args:
        fig: matplotlib Figure object.
        
    Returns:
        float: The x-coordinate representing the absolute left-most rendered pixel 
               across all subplots, scaled as a figure fraction (0.0 to 1.0).
    """
    # 1. Force the rendering engine to compute layout and text widths
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    
    global_min_x0 = float('inf')
    
    # 2. Iterate through all axes to find the true global leftmost bounding box
    for ax in fig.axes:
        bbox_display = ax.get_tightbbox(renderer)
        if bbox_display and bbox_display.x0 < global_min_x0:
            global_min_x0 = bbox_display.x0
            
    # 3. Transform the display coordinates (pixels) back into figure fractions.
    bbox_fig = fig.transFigure.inverted().transform([global_min_x0, 0])
    
    return bbox_fig[0]


def visual_identity(fig):
    """
    Add the AOS red accent bar aligned to the absolute left of the chart components.

    Operates at the Figure level and re-anchors itself on every redraw (resize,
    tight_layout, savefig at a different DPI, elements added afterward, etc.),
    so it stays correctly positioned no matter what happens to the figure later.
    Call this any time after the figure is created -- call order no longer matters.
    """
    _W_IN, _H_IN = 0.92, 0.20

    rect = Rectangle(
        (0, 0), 0, 0,
        transform=fig.transFigure,
        facecolor=ECON_RED, edgecolor="none",
        clip_on=False, zorder=20,
    )
    fig.add_artist(rect)

    text = fig.text(
        0, 0, "AOS",
        transform=fig.transFigure,
        ha="center", va="center",
        color=WHITE, fontsize=7.0, fontweight="bold",
        zorder=21, family=SANS,
    )

    _state = {"updating": False}

    def _reposition(event=None):
        # Guard against re-entrancy: set_bounds/draw_idle below triggers
        # another draw_event, which would otherwise recurse indefinitely.
        if _state["updating"]:
            return
        _state["updating"] = True
        try:
            fw, fh = fig.get_size_inches()
            w, h = _W_IN / fw, _H_IN / fh
            y = 1.0 + (0.06 / fh)
            x_left = _get_leftmost_x(fig)

            rect.set_bounds(x_left, y, w, h)
            text.set_position((x_left + w / 2, y + h / 2))

            fig.canvas.draw_idle()
        finally:
            _state["updating"] = False

    _reposition()  # initial placement
    fig.canvas.mpl_connect('draw_event', _reposition)


def fig_title(fig, title: str, subtitle: str = None,
              fonte: str = DATA_SOURCE_CITATION, top: float = 0.82):
    """
    Add title, subtitle, and dynamically wrapped source annotation.
    Enforces a strict layout calculation to prevent overlapping subplots.
    """
    # 1. Enforce strict collision detection layout.
    # This automatically calculates and applies the correct 'wspace' (width space) 
    # to prevent y-axis labels from bleeding into adjacent subplots.
    # The 'rect' bounds reserve space for our custom titles at the top and footnotes at the bottom.
    fig.tight_layout(rect=[0, 0.05, 1, top])
    
    # 2. Extract the absolute left boundary across ALL axes
    x_left = _get_leftmost_x(fig)
    
    # 3. Text Wrapping Math (Refactored for global figure width)
    # Calculates the available physical width from the leftmost boundary to the right edge
    # to ensure footnote wrapping spans the entire figure uniformly.
    fig_width_in = fig.get_size_inches()[0]
    available_width_fraction = 0.95 - x_left 
    available_width_in = fig_width_in * available_width_fraction
    
    char_width_in = (7.5 * 0.5) / 72
    max_chars = int(available_width_in / char_width_in)
    
    if fonte:
        wrapped_lines = [textwrap.fill(line, width=max_chars) for line in fonte.split('\n')]
        fonte_wrapped = '\n'.join(wrapped_lines)
        
    # 4. Text Placement
    fig.text(
        x_left, _TITLE_Y, title,
        ha="left", va="bottom",
        transform=fig.transFigure,
        family=SERIF, fontsize=14, fontweight="bold", color=CHARCOAL,
    )
    if subtitle:
        fig.text(
            x_left, _SUBTIT_Y, subtitle,
            ha="left", va="bottom",
            transform=fig.transFigure,
            family=SANS, fontsize=10, color=WARM_GREY,
        )
    if fonte:
        fig.text(
            x_left, -0.02, fonte_wrapped,
            ha="left", va="top",
            transform=fig.transFigure,
            family=SANS, fontsize=7.5, color=WARM_GREY, style="italic",
        )

def adjust_axis(ax, xlabel: str = None, ylabel: str = None):
    """
    Apply standard axis styling and enforce strict typographic compliance.
    
    This function aggressively overrides rogue font sizes and configurations 
    injected by third-party rendering libraries (e.g., SHAP, Seaborn), 
    ensuring maximum accuracy to the visual identity baseline.

    Args:
        ax:     matplotlib Axes object.
        xlabel: Optional x-axis label override.
        ylabel: Optional y-axis label override.
    """
    # 1. Update text string if explicitly provided by the user
    if xlabel:
        ax.set_xlabel(xlabel)
    if ylabel:
        ax.set_ylabel(ylabel)
        
    # 2. Extract and format the active labels (catches SHAP's auto-generated labels)
    xaxis_label = ax.xaxis.get_label()
    if xaxis_label:
        xaxis_label.set_size(9.5)
        xaxis_label.set_color(CHARCOAL)
        xaxis_label.set_family(SANS)
        
    yaxis_label = ax.yaxis.get_label()
    if yaxis_label:
        yaxis_label.set_size(9.5)
        yaxis_label.set_color(CHARCOAL)
        yaxis_label.set_family(SANS)

    # 3. Enforce tick label dimensions and colors
    ax.tick_params(axis='both', length=0, labelsize=9, colors=CHARCOAL)
    
    # 4. Enforce font family on all instantiated tick labels
    for label in ax.get_xticklabels() + ax.get_yticklabels():
        label.set_family(SANS)
        
    # 5. Spine formatting and cleanup
    for sp in ["left", "bottom"]:
        ax.spines[sp].set_color(WARM_GREY)
        ax.spines[sp].set_linewidth(0.8)
        ax.spines[sp].set_visible(True)
        
    for sp in ["top", "right"]:
        ax.spines[sp].set_visible(False)
        
    # 6. Strictly force grid lines to render behind all other artists
    ax.set_axisbelow(True)


def auto_scale_axis(ax, axis: str = 'y', label: str = None, prefix: str = ''):
    """
    Auto-scale an axis to a single consistent unit (K or M) based on its data
    range, and append the matching '(thousands)' / '(millions)' suffix to the
    axis label. Avoids the common bug of formatting each tick independently,
    which can mix units on the same axis (e.g. '900' next to '2K').

    Args:
        ax:     matplotlib Axes object.
        axis:   'y' or 'x'.
        label:  base axis label text (without the units suffix). If omitted,
                the axis label is left untouched.
        prefix: optional string prefix applied to every tick, e.g. '$'.
    """
    which_axis = ax.yaxis if axis == 'y' else ax.xaxis

    # Use the actual data limits (not the view limits) so the scale doesn't
    # change just because the user zooms or pans.
    data_min, data_max = ax.dataLim.intervaly if axis == 'y' else ax.dataLim.intervalx
    vmax = max(abs(data_min), abs(data_max))

    if vmax >= 1e6:
        suffix = "millions"
        fmt = lambda v: f'{prefix}{v / 1e6:.1f}M'
    elif vmax >= 1e3:
        suffix = "thousands"
        fmt = lambda v: f'{prefix}{v / 1e3:.0f}K'
    else:
        suffix = None
        fmt = lambda v: f'{prefix}{v:.0f}'

    which_axis.set_major_formatter(mticker.FuncFormatter(lambda v, pos=None: fmt(v)))

    if label is not None:
        full_label = f"{label} ({suffix})" if suffix else label
        if axis == 'y':
            ax.set_ylabel(full_label)
        else:
            ax.set_xlabel(full_label)


def fmt_num(v, pos=None):
    """Format large numbers: 1500 → '2K', 1500000 → '1.5M'."""
    if abs(v) >= 1e6:
        return f'{v / 1e6:.1f}M'
    if abs(v) >= 1e3:
        return f'{v / 1e3:.0f}K'
    return f'{v:.0f}'


def fmt_usd(v, pos=None):
    """Format USD amounts: 1500 → '$2K', 1500000 → '$1.5M'."""
    if abs(v) >= 1e6:
        return f'${v / 1e6:.1f}M'
    if abs(v) >= 1e3:
        return f'${v / 1e3:.0f}K'
    return f'${v:.0f}'


def bar_labels(ax, bars=None, fmt=None, horizontal: bool = False,
                prefix: str = '', headroom: float = 0.14,
                edge_threshold: float = 0.90, inside_color=WHITE,
                fontsize: float = 8.5):
    """
    Add value labels to a bar chart without letting them bleed outside the
    axes or into neighbouring subplots.

    Two mechanisms keep labels contained:
      1. Headroom: the axis limit on the value axis is expanded so the
         tallest/longest bar's label always has room to sit outside the bar.
      2. Edge fallback: any individual bar that's already close to the
         (expanded) limit gets its label drawn *inside* the bar instead of
         beyond it, so a single outlier can't force overflow.
    All label text is drawn with clip_on=True as a hard backstop.

    Args:
        ax:             matplotlib Axes object.
        bars:           BarContainer / list of Rectangle patches. Defaults to
                         ax.patches (i.e. whatever ax.bar/ax.barh produced).
        fmt:            callable(value) -> str. Defaults to fmt_num.
        horizontal:     True for ax.barh charts, False for ax.bar.
        prefix:         string prefix for the default formatter, e.g. '$'.
        headroom:       fraction of the data range reserved beyond the
                         tallest/longest bar for labels to sit in.
        edge_threshold: if a bar's value exceeds this fraction of the axis
                         max, its label is drawn inside the bar instead of
                         beyond its tip.
        inside_color:   text color used when a label is drawn inside a bar.
        fontsize:       label font size.
    """
    if bars is None:
        bars = ax.patches
    bars = list(bars)
    if not bars:
        return

    if fmt is None:
        fmt = lambda v: f'{prefix}{fmt_num(v)}'

    values = [(b.get_width() if horizontal else b.get_height()) for b in bars]
    vmax = max(values) if values else 0
    vmin = min(values) if values else 0
    span = max(vmax - min(0, vmin), 1e-9)

    if horizontal:
        cur_lo, cur_hi = ax.get_xlim()
        new_hi = max(cur_hi, vmax + span * headroom)
        ax.set_xlim(min(cur_lo, 0), new_hi)
        axis_max = new_hi
    else:
        cur_lo, cur_hi = ax.get_ylim()
        new_hi = max(cur_hi, vmax + span * headroom)
        ax.set_ylim(min(cur_lo, 0), new_hi)
        axis_max = new_hi

    pad_pts = 3
    for bar, val in zip(bars, values):
        label = fmt(val)
        near_edge = axis_max > 0 and (val / axis_max) >= edge_threshold

        if horizontal:
            y = bar.get_y() + bar.get_height() / 2
            if near_edge:
                ax.annotate(label, (val, y), xytext=(-pad_pts, 0),
                            textcoords="offset points", ha="right", va="center",
                            fontsize=fontsize, color=inside_color, family=SANS,
                            clip_on=True, zorder=15)
            else:
                ax.annotate(label, (val, y), xytext=(pad_pts, 0),
                            textcoords="offset points", ha="left", va="center",
                            fontsize=fontsize, color=CHARCOAL, family=SANS,
                            clip_on=True, zorder=15)
        else:
            x = bar.get_x() + bar.get_width() / 2
            if near_edge:
                ax.annotate(label, (x, val), xytext=(0, -pad_pts),
                            textcoords="offset points", ha="center", va="top",
                            fontsize=fontsize, color=inside_color, family=SANS,
                            clip_on=True, zorder=15)
            else:
                ax.annotate(label, (x, val), xytext=(0, pad_pts),
                            textcoords="offset points", ha="center", va="bottom",
                            fontsize=fontsize, color=CHARCOAL, family=SANS,
                            clip_on=True, zorder=15)


def truncar(s, n: int = 32) -> str:
    """Truncate a string to n characters with ellipsis."""
    s = str(s)
    return s[:n] + "..." if len(s) > n else s


def render_table(df, title: str = None, fmt: dict = None):
    """Render a DataFrame as a clean HTML table (Datawrapper-inspired).

    Args:
        df:    pandas DataFrame.
        title: Optional heading above the table.
        fmt:   Dict mapping column names to format strings.
               e.g. {'Payment': '${:,.0f}', 'Ratio': '{:.2f}'}
    """
    from IPython.display import display, HTML

    styled = df.style
    if fmt:
        styled = styled.format(fmt)

    css = """
    <style>
        .dw-table { border-collapse: collapse; font-family: Calibri, Arial, sans-serif;
                     font-size: 12px; width: 100%; margin: 8px 0;
                     background-color: #FFFFFF; }
        .dw-table th { text-align: center; font-weight: bold; padding: 10px 12px;
                       border-bottom: 2px solid #2D2926; color: #2D2926;
                       background-color: #F8F7F4; }
        .dw-table td { text-align: center; padding: 8px 12px; border-bottom: 1px solid #EDE5D8;
                       color: #2D2926; background-color: #FFFFFF; }
        .dw-table tr:last-child td { border-bottom: 2px solid #2D2926; }
        .dw-table tr:hover td { background-color: #F8F7F4; }
        .dw-title { font-family: Georgia, serif; font-size: 14px; font-weight: bold;
                     color: #2D2926; margin-bottom: 4px; background-color: #FFFFFF;}
    </style>
    """

    html = styled.set_table_attributes('class="dw-table"').hide(axis='index').to_html()
    if title:
        html = f'<div class="dw-title">{title}</div>' + html
    display(HTML(css + html))