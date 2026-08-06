using Godot;

public partial class Chevron : Control
{
    public bool PointsRight { get; set; }
    public Color StrokeColor { get; set; } = Colors.White;
    public float StrokeWidth { get; set; } = 6f;
    public float ArmHalfWidth { get; set; } = 4f;
    public float ArmHalfHeight { get; set; } = 20f;

    public override void _Draw()
    {
        Vector2 center = Size / 2f;
        float apexX = PointsRight ? ArmHalfWidth + 5 : -ArmHalfWidth - 5;
        float armX = -apexX;

        Vector2 apex = center + new Vector2(apexX + (PointsRight ? 7f : -7f), 0f);
        Vector2 top = center + new Vector2(armX, -ArmHalfHeight);
        Vector2 bottom = center + new Vector2(armX, ArmHalfHeight);

        DrawLine(top, apex, StrokeColor, StrokeWidth, true);
        DrawLine(apex, bottom, StrokeColor, StrokeWidth, true);

        // DrawLine has no cap-style option, so round the joints/tips by
        // stamping a circle the width of the stroke at each endpoint.
        float capRadius = StrokeWidth / 2f;
        DrawCircle(top, capRadius, StrokeColor);
        DrawCircle(apex, capRadius, StrokeColor);
        DrawCircle(bottom, capRadius, StrokeColor);
    }
}
