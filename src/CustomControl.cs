using Godot;

// A Control base for custom-drawn widgets: SetField() lets a derived
// class's property setters queue a redraw automatically, but only when the
// new value actually differs from the current one, so callers don't have
// to remember to call QueueRedraw() by hand after every mutation (and
// setting several properties in a row before the next frame doesn't queue
// redundant redraws).
public partial class CustomControl : Control
{
    protected void SetField<T>(ref T field, T value)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return;
        field = value;
        QueueRedraw();
    }
}
