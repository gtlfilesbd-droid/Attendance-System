from django import template

register = template.Library()


@register.filter(name='hours_to_hms')
def hours_to_hhmmss(value):
    """Convert decimal hours to HH:MM:SS format."""
    if value is None:
        return '—'
    try:
        h = float(value)
        total_secs = int(round(h * 3600))
        hrs = total_secs // 3600
        mins = (total_secs % 3600) // 60
        secs = total_secs % 60
        return f"{hrs:02d}:{mins:02d}:{secs:02d}"
    except (TypeError, ValueError):
        return '—'
