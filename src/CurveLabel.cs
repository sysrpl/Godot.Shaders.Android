using Godot;

// Where Text sits relative to its anchor: Point itself in
// CurveLabelMode.Point, or the curve's start/end/midpoint in
// CurveLabelMode.Curve.
public enum TextAlignment
{
    // Point mode: text is centered horizontally on Point too.
    // Curve mode: text is centered on the curve's midpoint (by arc length).
    Centered,
    // Point mode: Point is the text's left edge; text extends rightward
    // from it.
    // Curve mode: text starts at the curve's own start (arc length 0) and
    // flows forward - the default/original behavior.
    Left,
    // Point mode: Point is the text's right edge; text extends leftward
    // from it.
    // Curve mode: text ends at the curve's end (arc length equal to the
    // curve's length) and flows backward from there.
    Right,
}

public enum CurveLabelMode
{
    Curve,
    Point,
}

// A Control that draws a string one glyph at a time, either along a Curve2D
// (each glyph rotated to match the curve's tangent at its position) or
// anchored to a single point, per Mode. In both modes the text is centered
// vertically on the curve/point (rather than sitting on top of it,
// baseline-down, the way a plain Label would).
//
// For curve mode, set Curve to a Curve2D whose points are in this control's
// local space; set ScrollSpeed to animate the text flowing along it (on top
// of wherever Alignment places its start), or leave it at 0 for a static
// layout. Point doubles as that curve's offset in curve mode, so the curve
// can be moved without redefining its points. For point mode, Point is the
// anchor itself. Only ASCII/BMP characters are supported (glyphs are
// iterated as plain chars, not Unicode runes, so surrogate pairs would
// render as two boxes rather than one glyph).
public partial class CurveLabel : CustomControl
{
    public CurveLabel()
    {
        MouseFilter = MouseFilterEnum.Ignore;
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
    }

    // Another Control whose Position is added to Point (and to every curve
    // sample, in curve mode), so this label can track something that moves
    // - e.g. an image it's meant to label - without recomputing Point by
    // hand each time. Null means no extra offset.
    private Control _associate = null;
    public Control Associate
    {
        get => _associate;
        set => SetField(ref _associate, value);
    }

    private string _text = "";
    public string Text
    {
        get => _text;
        set => SetField(ref _text, value);
    }

    private Font _font;
    public Font Font
    {
        get => _font;
        set => SetField(ref _font, value);
    }

    private int _fontSize = 32;
    public int FontSize
    {
        get => _fontSize;
        set => SetField(ref _fontSize, value);
    }

    private Color _fontColor = Colors.White;
    public Color FontColor
    {
        get => _fontColor;
        set => SetField(ref _fontColor, value);
    }

    private int _outlineSize;
    public int OutlineSize
    {
        get => _outlineSize;
        set => SetField(ref _outlineSize, value);
    }

    private Color _outlineColor = Colors.Black;
    public Color OutlineColor
    {
        get => _outlineColor;
        set => SetField(ref _outlineColor, value);
    }

    private float _letterSpacing;
    public float LetterSpacing
    {
        get => _letterSpacing;
        set => SetField(ref _letterSpacing, value);
    }

    private CurveLabelMode _mode = CurveLabelMode.Curve;
    public CurveLabelMode Mode
    {
        get => _mode;
        set => SetField(ref _mode, value);
    }

    private Curve2D _curve;
    public Curve2D Curve
    {
        get => _curve;
        set => SetField(ref _curve, value);
    }

    // Pixels per second to advance along the curve; 0 keeps the layout static.
    private float _scrollSpeed;
    public float ScrollSpeed
    {
        get => _scrollSpeed;
        set => SetField(ref _scrollSpeed, value);
    }

    // When true, both the scroll offset and each glyph's sample distance
    // wrap around the curve's length instead of running off the end.
    private bool _loop = true;
    public bool Loop
    {
        get => _loop;
        set => SetField(ref _loop, value);
    }

    private Vector2 _point;
    public Vector2 Point
    {
        get => _point;
        set => SetField(ref _point, value);
    }

    private TextAlignment _alignment = TextAlignment.Centered;
    public TextAlignment Alignment
    {
        get => _alignment;
        set => SetField(ref _alignment, value);
    }

    // When true, draws a debug overlay on top of the text: the curve itself
    // (as a red stroke) in curve mode, or a red dot at Point in point mode.
    private bool _debug;
    public bool Debug
    {
        get => _debug;
        set => SetField(ref _debug, value);
    }

    private const float DebugStrokeWidth = 3f;
    private const float DebugDotRadius = 5f;

    // Points on Curve returns Vector2.Zero when no Curve is assigned.
    public Vector2 CurveStart => Curve is null ? Vector2.Zero : Curve.SampleBaked(0f, true);
    public Vector2 CurveMiddle => Curve is null ? Vector2.Zero : Curve.SampleBaked(Curve.GetBakedLength() / 2f, true);
    public Vector2 CurveEnd => Curve is null ? Vector2.Zero : Curve.SampleBaked(Curve.GetBakedLength(), true);

    private float _scrollOffset;

    // Point plus Associate's own position, if any - the actual world/local
    // offset applied to Point and to every curve sample.
    private Vector2 ComputedPoint => Point + (Associate is null ? Vector2.Zero : Associate.Position);

    public override void _Process(double delta)
    {
        if (Mode != CurveLabelMode.Curve || ScrollSpeed == 0f || Curve == null)
            return;
        float length = Curve.GetBakedLength();
        if (length <= 0f)
            return;
        _scrollOffset += (float)delta * ScrollSpeed;
        if (Loop)
            _scrollOffset = Mathf.PosMod(_scrollOffset, length);
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (string.IsNullOrEmpty(Text) && !Debug)
            return;
        Font font = Font ?? ThemeDB.FallbackFont;
        int fontSize = Font != null ? FontSize : ThemeDB.FallbackFontSize;
        // Offset from the anchor (a curve sample point or Point) down to the
        // glyph baseline, so the glyph's own vertical center - not its
        // baseline - lands on the anchor.
        float baselineOffset = (font.GetAscent(fontSize) - font.GetDescent(fontSize)) / 2f;
        Rid canvas = GetCanvasItem();
        if (!string.IsNullOrEmpty(Text))
        {
            if (Mode == CurveLabelMode.Curve)
                DrawAlongCurve(font, fontSize, baselineOffset, canvas);
            else
                DrawAtPoint(font, fontSize, baselineOffset, canvas);
        }
        // Drawn last (rather than first) so the overlay sits on top of the
        // text instead of underneath it.
        if (Debug)
            DrawDebug();
    }

    private void DrawDebug()
    {
        Vector2 p = ComputedPoint;
        if (Mode == CurveLabelMode.Curve)
        {
            if (Curve == null)
                return;
            Vector2[] points = Curve.Tessellate();
            for (int i = 0; i < points.Length; i++)
                points[i] += p;
            DrawPolyline(points, Colors.Red, DebugStrokeWidth);
        }
        else
            DrawCircle(p, DebugDotRadius, Colors.Red);
    }

    private void DrawAlongCurve(Font font, int fontSize, float baselineOffset, Rid canvas)
    {
        if (Curve == null)
            return;

        float length = Curve.GetBakedLength();
        if (length <= 0f)
            return;

        // Left starts the text at the curve's own start (arc length 0, the
        // existing/default behavior); Right ends it at the curve's end
        // (arc length `length`); Centered centers it on the curve's
        // midpoint. ScrollSpeed then animates on top of whichever start
        // point that lands on.
        float startDistance = Alignment switch
        {
            TextAlignment.Right => length - MeasureTextWidth(font, fontSize),
            TextAlignment.Centered => (length - MeasureTextWidth(font, fontSize)) / 2f,
            _ => 0f,
        };
        float cursor = startDistance + _scrollOffset;
        Vector2 p = ComputedPoint;
        foreach (char c in Text)
        {
            long code = c;
            float charWidth = font.GetCharSize(code, fontSize).X;
            float sampleDistance = cursor + charWidth / 2f;

            if (Loop)
                sampleDistance = Mathf.PosMod(sampleDistance, length);
            else if (sampleDistance < 0f || sampleDistance > length)
            {
                cursor += charWidth + LetterSpacing;
                continue;
            }
            Transform2D t = Curve.SampleBakedWithRotation(sampleDistance, true);
            Vector2 glyphPos = new(-charWidth / 2f, baselineOffset);
            DrawSetTransform(t.Origin + p, t.Rotation, Vector2.One);
            if (OutlineSize > 0)
                font.DrawCharOutline(canvas, glyphPos, code, fontSize, OutlineSize, OutlineColor);
            font.DrawChar(canvas, glyphPos, code, fontSize, FontColor);
            cursor += charWidth + LetterSpacing;
        }
        DrawSetTransform(Vector2.Zero, 0f, Vector2.One);
    }

    private float MeasureTextWidth(Font font, int fontSize)
    {
        float totalWidth = -LetterSpacing;
        foreach (char c in Text)
            totalWidth += font.GetCharSize(c, fontSize).X + LetterSpacing;
        return totalWidth;
    }

    private void DrawAtPoint(Font font, int fontSize, float baselineOffset, Rid canvas)
    {
        float totalWidth = MeasureTextWidth(font, fontSize);
        Vector2 p = ComputedPoint;
        float cursor = Alignment switch
        {
            TextAlignment.Left => p.X,
            TextAlignment.Right => p.X - totalWidth,
            _ => p.X - totalWidth / 2f,
        };
        float baselineY = p.Y + baselineOffset;
        foreach (char c in Text)
        {
            long code = c;
            float charWidth = font.GetCharSize(code, fontSize).X;
            Vector2 glyphPos = new(cursor, baselineY);
            if (OutlineSize > 0)
                font.DrawCharOutline(canvas, glyphPos, code, fontSize, OutlineSize, OutlineColor);
            font.DrawChar(canvas, glyphPos, code, fontSize, FontColor);
            cursor += charWidth + LetterSpacing;
        }
    }
}
