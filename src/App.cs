using Godot;
using Codebot.Godot;

public partial class Main : Node3D
{
    private const string ShaderDir = "res://resources/shaders/";
    private const string ShaderTitlePrefix = "// title:";

    private const float TransitionSeconds = 1.0f;
    private const float SwipeThreshold = 80f;
    private const int TitleBottomMargin = 40;
    private const string SettingsPath = "user://settings.tres";
    private const int DefaultScale = 4;

    private void Quit()
    {
        SaveSettings();
        GetTree().Quit();
    }
    private CanvasLayer _canvas;
    private RenderBuffer _renderBuffer;
    private Button _quitButton;
    private ColorRect _renderAreaA;
    private ColorRect _renderAreaB;
    private ColorRect _activeRenderArea;
    private Label _titleLabelA;
    private Label _titleLabelB;
    private Label _fpsLabel;
    private Slider _scaleSlider;
    private bool _sliderDragging;
    private readonly Dictionary<string, string> _shaderTitles = [];
    private readonly Dictionary<string, ShaderMaterial> _shaderMaterials = [];
    private readonly List<string> _shaderPaths = [];
    private int _currentShaderIndex;
    private bool _isTransitioning;
    private Vector2 _touchStartPosition;
    private bool _touchTracking;
    private readonly List<(Control Control, Action OnClick)> _tapTargets = [];

    public override void _Ready()
    {
        _canvas = GetNode<CanvasLayer>("UI");
        LoadShaderTitles();

        _renderBuffer = new RenderBuffer();
        AddChild(_renderBuffer);
        // Skip the extra offscreen-buffer copy entirely once the slider is
        // dragged back down to 1x (no downscaling requested).
        _renderBuffer.DirectRender = true;
        // Restore the last saved scale (half resolution -> a quarter as
        // many fragments for the raymarched shaders to shade - by default,
        // until the user's chosen a different one via the slider).
        _renderBuffer.Scale = LoadSettings().Scale;

        _renderAreaA = CreateRenderArea("RenderAreaA");
        _renderAreaB = CreateRenderArea("RenderAreaB");
        _renderAreaB.Visible = false;
        _activeRenderArea = _renderAreaA;

        // Parented to the canvas (full resolution), not the render areas,
        // so the title text isn't downscaled along with the shader - their
        // slide during a transition is instead synced manually in
        // TransitionToShader.
        _titleLabelA = CreateTitleLabel();
        _titleLabelB = CreateTitleLabel();
        _titleLabelB.Visible = false;

        SetRenderShader(ShaderDir + "grated.gdshader");

        _quitButton = new Button { Text = "Quit" };
        _canvas.AddChild(_quitButton);
        _quitButton.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.TopRight, Control.LayoutPresetMode.Minsize, 20);
        _quitButton.Pressed += Quit;

        _fpsLabel = new Label { Name = "FpsLabel" };
        _fpsLabel.AddThemeStyleboxOverride("normal", CreatePanelBackground());
        _canvas.AddChild(_fpsLabel);
        _fpsLabel.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.TopLeft, Control.LayoutPresetMode.Minsize, 20);

        // Sits just above the title box - measured from the title's own
        // rendered height rather than a guessed constant, since that height
        // is already known (fixed content margins + a single line of text).
        const float sliderHeight = 24f;
        float sliderBottomMargin = TitleBottomMargin + _titleLabelA.Size.Y + 16f;
        _scaleSlider = new HSlider
        {
            Name = "ScaleSlider",
            MinValue = RenderBuffer.MinShrink,
            MaxValue = RenderBuffer.MaxShrink,
            Step = 1,
            Value = _renderBuffer.Scale,
        };

        // One StyleBox reused for both the track and the filled portion, so
        // the whole bar reads as a single solid white shape rather than
        // distinguishing "filled" from "remaining".
        var barStyle = new StyleBoxFlat
        {
            BgColor = Colors.White,
            CornerRadiusTopLeft = (int)(sliderHeight / 2),
            CornerRadiusTopRight = (int)(sliderHeight / 2),
            CornerRadiusBottomLeft = (int)(sliderHeight / 2),
            CornerRadiusBottomRight = (int)(sliderHeight / 2),
        };
        _scaleSlider.AddThemeStyleboxOverride("slider", barStyle);
        _scaleSlider.AddThemeStyleboxOverride("grabber_area", barStyle);
        _scaleSlider.AddThemeStyleboxOverride("grabber_area_highlight", barStyle);

        // Same opaque white circle texture for every grabber state (normal/
        // hover/disabled) - Slider has no separate "pressed" icon, dragging
        // just keeps showing the hover one.
        var thumbTexture = CreateThumbTexture(diameter: 14, outline: 0);
        _scaleSlider.AddThemeIconOverride("grabber", thumbTexture);
        _scaleSlider.AddThemeIconOverride("grabber_highlight", thumbTexture);
        _scaleSlider.AddThemeIconOverride("grabber_disabled", thumbTexture);

        _canvas.AddChild(_scaleSlider);
        // Middle 50% of the width, so it's centered with no separate margin.
        _scaleSlider.AnchorLeft = 0.25f;
        _scaleSlider.AnchorRight = 0.75f;
        _scaleSlider.AnchorTop = 1f;
        _scaleSlider.AnchorBottom = 1f;
        _scaleSlider.OffsetLeft = 0f;
        _scaleSlider.OffsetRight = 0f;
        _scaleSlider.OffsetBottom = -sliderBottomMargin;
        _scaleSlider.OffsetTop = -sliderBottomMargin - sliderHeight;
        _scaleSlider.ValueChanged += value => _renderBuffer.Scale = (int)value;

        AddNavCircle(alignLeft: true, () => StepShader(-1));
        AddNavCircle(alignLeft: false, () => StepShader(1));
    }

    public override void _Process(double delta)
    {
        var percent = 1 / MathF.Pow(2, _renderBuffer.Scale - 1) * 100f;
        _fpsLabel.Text = $"{percent:F0}% at {Engine.GetFramesPerSecond()} FPS";
        _scaleSlider.Value = _renderBuffer.Scale;
    }

    // Catches the OS close button (clicking the window's X); our own Quit()
    // (Escape key / quit button) already saves directly since it's a single
    // choke point we control. Godot still auto-quits after this either way.
    public override void _Notification(int what)
    {
        if (what == NotificationWMCloseRequest)
        {
            SaveSettings();
        }
    }

    private static AppSettings LoadSettings()
    {
        if (ResourceLoader.Exists(SettingsPath) && GD.Load<AppSettings>(SettingsPath) is AppSettings settings)
        {
            return settings;
        }
        return new AppSettings { Scale = DefaultScale };
    }

    private void SaveSettings()
    {
        var settings = new AppSettings { Scale = _renderBuffer.Scale };
        ResourceSaver.Save(settings, SettingsPath);
    }

    // A solid white circle with a black outline ring, used for every
    // grabber theme state so the thumb is always fully opaque.
    private static ImageTexture CreateThumbTexture(int diameter, int outline)
    {
        var image = Image.CreateEmpty(diameter, diameter, false, Image.Format.Rgba8);
        float center = diameter / 2f;
        float outerRadius = diameter / 2f;
        float innerRadius = outerRadius - outline;

        for (int y = 0; y < diameter; y++)
        {
            for (int x = 0; x < diameter; x++)
            {
                float dist = new Vector2(x + 0.5f - center, y + 0.5f - center).Length();
                Color color = dist > outerRadius ? Colors.Transparent : dist > innerRadius ? Colors.Black : Colors.White;
                image.SetPixel(x, y, color);
            }
        }

        return ImageTexture.CreateFromImage(image);
    }

    private ColorRect CreateRenderArea(string name)
    {
        var renderArea = new ColorRect { Name = name };
        renderArea.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        _renderBuffer.RenderViewport.AddChild(renderArea);
        return renderArea;
    }

    private static StyleBoxFlat CreatePanelBackground() => new()
    {
        BgColor = Colors.Black,
        ContentMarginLeft = 20,
        ContentMarginTop = 20,
        ContentMarginRight = 20,
        ContentMarginBottom = 20,
        CornerRadiusTopLeft = 20,
        CornerRadiusTopRight = 20,
        CornerRadiusBottomLeft = 20,
        CornerRadiusBottomRight = 20,
    };

    private Label CreateTitleLabel()
    {
        var label = new Label
        {
            Name = "TitleLabel",
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        label.AddThemeStyleboxOverride("normal", CreatePanelBackground());
        _canvas.AddChild(label);
        return label;
    }

    private Label GetTitleLabel(ColorRect renderArea) => renderArea == _renderAreaA ? _titleLabelA : _titleLabelB;

    private void StepShader(int direction)
    {
        if (_isTransitioning || _shaderPaths.Count == 0)
        {
            return;
        }

        _currentShaderIndex = (_currentShaderIndex + direction + _shaderPaths.Count) % _shaderPaths.Count;
        TransitionToShader(_shaderPaths[_currentShaderIndex], direction);
    }

    private void TransitionToShader(string path, int direction)
    {
        _isTransitioning = true;

        var outgoing = _activeRenderArea;
        var incoming = outgoing == _renderAreaA ? _renderAreaB : _renderAreaA;
        var outgoingTitle = GetTitleLabel(outgoing);
        var incomingTitle = GetTitleLabel(incoming);

        incoming.Material = GetOrLoadShaderMaterial(path);
        incomingTitle.Text = _shaderTitles.TryGetValue(path, out var title) ? title : "";
        incomingTitle.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.CenterBottom, Control.LayoutPresetMode.Minsize, TitleBottomMargin);

        // The render areas live inside RenderBuffer's downscaled SubViewport,
        // but the titles live directly on the (full-resolution) canvas, so
        // each needs its slide distance measured in its own viewport.
        float bufferWidth = incoming.GetViewport().GetVisibleRect().Size.X;
        float windowWidth = GetViewport().GetVisibleRect().Size.X;
        // direction > 0 (next/right chevron): incoming enters from the right, outgoing exits to the left.
        // direction < 0 (prev/left chevron): incoming enters from the left, outgoing exits to the right.
        float bufferStartX = direction > 0 ? bufferWidth : -bufferWidth;
        float bufferEndX = -bufferStartX;
        float windowStartX = direction > 0 ? windowWidth : -windowWidth;
        float windowEndX = -windowStartX;

        incoming.OffsetLeft = bufferStartX;
        incoming.OffsetRight = bufferStartX;
        incoming.Visible = true;

        // Titles are positioned as an offset from their own centered resting
        // position (captured here) rather than from 0, since that resting
        // position isn't the same for both titles when their text differs.
        float incomingTitleLeft = incomingTitle.OffsetLeft;
        float incomingTitleRight = incomingTitle.OffsetRight;
        float outgoingTitleLeft = outgoingTitle.OffsetLeft;
        float outgoingTitleRight = outgoingTitle.OffsetRight;

        incomingTitle.OffsetLeft = incomingTitleLeft + windowStartX;
        incomingTitle.OffsetRight = incomingTitleRight + windowStartX;
        incomingTitle.Visible = true;

        var tween = CreateTween();
        tween.SetParallel(true);
        tween.SetTrans(Tween.TransitionType.Cubic);
        tween.SetEase(Tween.EaseType.InOut);
        tween.TweenMethod(Callable.From<float>(x =>
        {
            incoming.OffsetLeft = x;
            incoming.OffsetRight = x;
        }), bufferStartX, 0f, TransitionSeconds);
        tween.TweenMethod(Callable.From<float>(x =>
        {
            outgoing.OffsetLeft = x;
            outgoing.OffsetRight = x;
        }), 0f, bufferEndX, TransitionSeconds);
        tween.TweenMethod(Callable.From<float>(x =>
        {
            incomingTitle.OffsetLeft = incomingTitleLeft + x;
            incomingTitle.OffsetRight = incomingTitleRight + x;
        }), windowStartX, 0f, TransitionSeconds);
        tween.TweenMethod(Callable.From<float>(x =>
        {
            outgoingTitle.OffsetLeft = outgoingTitleLeft + x;
            outgoingTitle.OffsetRight = outgoingTitleRight + x;
        }), 0f, windowEndX, TransitionSeconds);
        tween.Chain().TweenCallback(Callable.From(() =>
        {
            outgoing.Visible = false;
            outgoing.OffsetLeft = 0f;
            outgoing.OffsetRight = 0f;
            outgoingTitle.Visible = false;
            outgoingTitle.OffsetLeft = outgoingTitleLeft;
            outgoingTitle.OffsetRight = outgoingTitleRight;
            _activeRenderArea = incoming;
            _isTransitioning = false;
        }));
    }

    private ShaderMaterial GetOrLoadShaderMaterial(string path)
    {
        if (!_shaderMaterials.TryGetValue(path, out var material))
        {
            material = new ShaderMaterial { Shader = GD.Load<Shader>(path) };
            _shaderMaterials[path] = material;
        }
        return material;
    }

    private void AddNavCircle(bool alignLeft, Action onClick)
    {
        const float diameter = 80f;
        const float edgeMargin = 20f;

        // A Button (rather than a plain Panel + GuiInput) so clicking reuses
        // the same input path already proven to work for the quit button.
        var circle = new Button
        {
            Name = alignLeft ? "PrevCircle" : "NextCircle",
            CustomMinimumSize = new Vector2(diameter, diameter),
            Flat = true,
            MouseDefaultCursorShape = Control.CursorShape.PointingHand,
        };
        var ring = new StyleBoxFlat
        {
            DrawCenter = false,
            BorderWidthLeft = 6,
            BorderWidthTop = 6,
            BorderWidthRight = 6,
            BorderWidthBottom = 6,
            BorderColor = Colors.White,
            CornerRadiusTopLeft = (int)(diameter / 2),
            CornerRadiusTopRight = (int)(diameter / 2),
            CornerRadiusBottomLeft = (int)(diameter / 2),
            CornerRadiusBottomRight = (int)(diameter / 2),
        };
        circle.AddThemeStyleboxOverride("normal", ring);
        circle.AddThemeStyleboxOverride("hover", ring);
        circle.AddThemeStyleboxOverride("pressed", ring);
        circle.AddThemeStyleboxOverride("focus", ring);
        circle.Pressed += onClick;
        _canvas.AddChild(circle);

        // project.godot disables pointing/emulate_mouse_from_touch, so Button
        // never sees a click from a touch tap; hit-test it manually instead.
        _tapTargets.Add((circle, onClick));

        // Anchor to the near edge at mid-height, then offset in explicitly so
        // both sides are mirror images of each other (rather than trusting
        // the preset's own margin sign convention to be symmetric).
        circle.AnchorLeft = alignLeft ? 0f : 1f;
        circle.AnchorRight = alignLeft ? 0f : 1f;
        circle.AnchorTop = 0.5f;
        circle.AnchorBottom = 0.5f;
        circle.OffsetLeft = alignLeft ? edgeMargin : -edgeMargin - diameter;
        circle.OffsetRight = alignLeft ? edgeMargin + diameter : -edgeMargin;
        circle.OffsetTop = -diameter / 2f;
        circle.OffsetBottom = diameter / 2f;

        // Set position/size directly (rather than anchoring to FullRect) so
        // the chevron's Size is correct the moment _Draw() first reads it,
        // with no dependency on a parent layout pass having already run.
        var chevron = new Chevron
        {
            PointsRight = !alignLeft,
            Position = Vector2.Zero,
            Size = new Vector2(diameter, diameter),
            MouseFilter = Control.MouseFilterEnum.Ignore,
        };
        circle.AddChild(chevron);
    }

    private void LoadShaderTitles()
    {
        using var dir = DirAccess.Open(ShaderDir);
        if (dir == null)
        {
            return;
        }

        dir.ListDirBegin();
        for (string fileName = dir.GetNext(); fileName != ""; fileName = dir.GetNext())
        {
            if (!fileName.EndsWith(".gdshader"))
            {
                continue;
            }

            string path = ShaderDir + fileName;
            _shaderTitles[path] = ReadShaderTitle(path);
            _shaderPaths.Add(path);
        }
        dir.ListDirEnd();
        _shaderPaths.Sort();
    }

    private static string ReadShaderTitle(string path)
    {
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
        if (file == null)
        {
            return "";
        }

        string firstLine = file.GetLine();
        return firstLine.StartsWith(ShaderTitlePrefix)
            ? firstLine.Substring(ShaderTitlePrefix.Length).Trim()
            : Path.GetFileNameWithoutExtension(path);
    }

    private void SetRenderShader(string path)
    {
        _activeRenderArea.Material = GetOrLoadShaderMaterial(path);
        var titleLabel = GetTitleLabel(_activeRenderArea);
        titleLabel.Text = _shaderTitles.TryGetValue(path, out var title) ? title : "";
        titleLabel.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.CenterBottom, Control.LayoutPresetMode.Minsize, TitleBottomMargin);
        _currentShaderIndex = _shaderPaths.IndexOf(path);
    }

    private void TakeScreenshot()
    {
        Image image = GetViewport().GetTexture().GetImage();
        string path = ProjectSettings.GlobalizePath("res://docs/snapshot.png");
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        image.SavePng(path);
    }

    public override void _Input(InputEvent input)
    {
        if (input is InputEventKey keyEvent && keyEvent.Pressed && !keyEvent.Echo)
        {
            if (keyEvent.Keycode == Key.F1)
            {
                DisplayServer.WindowSetMode(DisplayServer.WindowGetMode() == DisplayServer.WindowMode.Fullscreen
                    ? DisplayServer.WindowMode.Windowed
                    : DisplayServer.WindowMode.Fullscreen);
            }
            else if (keyEvent.Keycode == Key.F2)
                TakeScreenshot();
            else if (keyEvent.Keycode == Key.Escape)
                Quit();
            else if (keyEvent.Keycode == Key.Left)
                StepShader(-1);
            else if (keyEvent.Keycode == Key.Right)
                StepShader(1);
            else if (keyEvent.Keycode == Key.Up)
                _renderBuffer.Scale--;
            else if (keyEvent.Keycode == Key.Down)
                _renderBuffer.Scale++;
        }
        else if (input is InputEventScreenTouch touch)
        {
            if (touch.Pressed)
            {
                if (_scaleSlider.GetGlobalRect().HasPoint(touch.Position))
                {
                    _sliderDragging = true;
                    UpdateSliderFromTouch(touch.Position);
                }
                else
                {
                    _touchStartPosition = touch.Position;
                    _touchTracking = true;
                }
            }
            else if (_sliderDragging)
            {
                _sliderDragging = false;
            }
            else if (_touchTracking)
            {
                _touchTracking = false;

                foreach (var (control, onClick) in _tapTargets)
                {
                    if (control.GetGlobalRect().HasPoint(touch.Position))
                    {
                        onClick();
                        return;
                    }
                }

                Vector2 delta = touch.Position - _touchStartPosition;
                if (Mathf.Abs(delta.X) > SwipeThreshold && Mathf.Abs(delta.X) > Mathf.Abs(delta.Y))
                {
                    StepShader(delta.X < 0 ? 1 : -1);
                }
            }
        }
        else if (input is InputEventScreenDrag drag && _sliderDragging)
        {
            UpdateSliderFromTouch(drag.Position);
        }
    }

    // project.godot disables pointing/emulate_mouse_from_touch, so Slider
    // (like Button) never sees drags from touch; drive it manually.
    private void UpdateSliderFromTouch(Vector2 globalPos)
    {
        Rect2 rect = _scaleSlider.GetGlobalRect();
        double t = Mathf.Clamp((globalPos.X - rect.Position.X) / rect.Size.X, 0f, 1f);
        _scaleSlider.Value = _scaleSlider.MinValue + t * (_scaleSlider.MaxValue - _scaleSlider.MinValue);
    }
}
