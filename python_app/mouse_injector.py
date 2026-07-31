# =========================================================================
# INJEÇÃO DE EVENTOS NO MACOS — CGEvent via Quartz (pyobjc)
# Mesma API nativa que usávamos no Swift (CGEvent).
# =========================================================================
import Quartz
import subprocess


# Constantes de tipo de evento para facilitar uso externo
MOUSE_MOVED = Quartz.kCGEventMouseMoved
LEFT_MOUSE_DOWN = Quartz.kCGEventLeftMouseDown
LEFT_MOUSE_UP = Quartz.kCGEventLeftMouseUp
LEFT_MOUSE_DRAGGED = Quartz.kCGEventLeftMouseDragged
RIGHT_MOUSE_DOWN = Quartz.kCGEventRightMouseDown
RIGHT_MOUSE_UP = Quartz.kCGEventRightMouseUp
RIGHT_MOUSE_DRAGGED = Quartz.kCGEventRightMouseDragged


def get_screen_bounds() -> tuple[float, float]:
    """Retorna (width, height) da tela principal."""
    bounds = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
    return bounds.size.width, bounds.size.height


def post_mouse_event(
    event_type: int,
    point: tuple[float, float],
    click_count: int = 1,
    is_right_click: bool = False,
):
    """
    Injeta um evento de mouse no macOS usando CGEvent.
    
    Args:
        event_type: Tipo do evento (MOUSE_MOVED, LEFT_MOUSE_DOWN, etc.)
        point: (x, y) em coordenadas absolutas da tela.
        click_count: Contagem de cliques (1 = simples, 2 = duplo).
        is_right_click: Se True, converte o evento para botão direito.
    """
    final_type = event_type
    button = Quartz.kCGMouseButtonLeft

    if is_right_click:
        button = Quartz.kCGMouseButtonRight
        if event_type == LEFT_MOUSE_DOWN:
            final_type = RIGHT_MOUSE_DOWN
        elif event_type == LEFT_MOUSE_UP:
            final_type = RIGHT_MOUSE_UP
        elif event_type == LEFT_MOUSE_DRAGGED:
            final_type = RIGHT_MOUSE_DRAGGED

    cg_point = Quartz.CGPointMake(point[0], point[1])
    event = Quartz.CGEventCreateMouseEvent(None, final_type, cg_point, button)

    if event:
        Quartz.CGEventSetIntegerValueField(
            event, Quartz.kCGMouseEventClickState, click_count
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

    # Som de feedback no clique
    if final_type in (LEFT_MOUSE_DOWN, RIGHT_MOUSE_DOWN):
        _play_click_sound()


def post_scroll_event(scroll_speed: float):
    """Injeta um evento de scroll wheel no macOS."""
    event = Quartz.CGEventCreateScrollWheelEvent(
        None,
        Quartz.kCGScrollEventUnitPixel,
        1,  # wheelCount
        int(scroll_speed),
    )
    if event:
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def _play_click_sound():
    """Toca o som 'Pop' do sistema como feedback de clique."""
    try:
        subprocess.Popen(
            ["afplay", "/System/Library/Sounds/Pop.aiff"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass  # Silenciosamente ignora se não conseguir tocar o som
