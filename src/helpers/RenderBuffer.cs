using Godot;

namespace Codebot.Godot;

// Renders whatever is added as a child of RenderViewport into an off-screen
// SubViewport at a runtime-adjustable fraction of the window's linear
// resolution, then displays that buffer stretched back up to fill the
// window using nearest-neighbor (blocky) filtering. A smaller framebuffer
// means less per-pixel GPU work (shading, SSAO, SSR, fragment shaders);
// per-object costs like shadows and physics are unaffected.
//
// Add an instance as a child of your scene root, then AddChild() whatever
// should be downscaled (2D or 3D) onto RenderViewport instead of onto the
// scene root directly. For 3D content, set TrackedCamera to whatever
// Camera3D should drive the render (e.g. an orbit rig's camera) - its
// transform is copied onto the internal render camera every frame. Call
// AdjustResolution() to step the resolution up/down by a factor of two,
// e.g. from user input.
public partial class RenderBuffer : Node
{
    public const int MinShrink = 1;
    public const int MaxShrink = 6;

    private SubViewport _viewport;
    private SubViewportContainer _container;
    private CanvasLayer _bufferedLayer;
    private CanvasLayer _directLayer;
    private Camera3D _renderCamera;

    // Add content to be downscaled here (2D or 3D) instead of under the
    // owning scene, so it renders through the SubViewport instead of
    // straight to the window. Nothing should ever be parented under
    // RenderBuffer itself - it manages its own internal children.
    //
    // When DirectRender is true and Scale is at MinShrink (no downscaling
    // requested), content is transparently moved to render straight into
    // the window instead of through this SubViewport, since buffering
    // through a same-resolution offscreen texture just to copy it back
    // would be a wasted extra GPU pass for zero visual benefit. This
    // property always reflects wherever content currently lives, so
    // AddChild() onto it works the same regardless of mode.
    public Node RenderViewport => IsDirectRender ? _directLayer : _viewport;

    // The live camera whose transform drives the render, copied onto the
    // internal render camera every frame; set this to e.g. an orbit rig's
    // Camera3D. Only relevant for 3D content added to RenderViewport.
    public Camera3D TrackedCamera { get; set; }

    public int ResolutionPercent => 100 / _scale;

    public override void _Ready()
    {
        // OwnWorld3D isolates this SubViewport's World3D from the parent
        // window's, so the window doesn't also render the same scene a
        // second time at full resolution.
        _viewport = new SubViewport
        {
            OwnWorld3D = true,
            // A manually created SubViewport doesn't inherit the
            // project's [rendering] anti_aliasing settings (those only
            // seed the root window's viewport), so match them explicitly.
            Msaa3D = Viewport.Msaa.Msaa4X,
            ScreenSpaceAA = Viewport.ScreenSpaceAAEnum.Fxaa
        };

        // MouseFilter = Ignore keeps this full-window Control out of the
        // GUI input pass, so it can't swallow mouse events meant for
        // unhandled-input-driven camera controls elsewhere in the scene.
        _container = new SubViewportContainer
        {
            Stretch = true,
            StretchShrink = _scale,
            MouseFilter = Control.MouseFilterEnum.Ignore,
            TextureFilter = CanvasItem.TextureFilterEnum.Nearest
        };
        _container.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _container.AddChild(_viewport);

        // Layer -1 keeps these reliably behind normal (default-layer) UI
        // CanvasLayers regardless of scene-tree add order.
        _bufferedLayer = new CanvasLayer { Layer = -1 };
        _bufferedLayer.AddChild(_container);
        AddChild(_bufferedLayer);

        // The direct-render bypass path: a plain CanvasLayer with no
        // SubViewport in between, so content parented here renders
        // straight into the window's own framebuffer.
        _directLayer = new CanvasLayer { Layer = -1, Visible = false };
        AddChild(_directLayer);

        _renderCamera = new Camera3D { Current = true };
        _viewport.AddChild(_renderCamera);

        UpdateRenderMode();
    }

    public override void _Process(double delta)
    {
        if (TrackedCamera != null)
            _renderCamera.GlobalTransform = TrackedCamera.GlobalTransform;
    }

    private bool _directRender;
    public bool DirectRender
    {
        get => _directRender;
        set
        {
            if (value == _directRender)
                return;
            _directRender = value;
            UpdateRenderMode();
        }
    }

    private bool IsDirectRender => _directRender && _scale == MinShrink;

    public void AdjustResolution(bool increase)
    {
        if (increase)
            Scale++;
        else
            Scale--;
    }

    private int _scale = 1;
    public int Scale
    {
        get => _scale;
        set
        {
            if (value < MinShrink)
                value = MinShrink;
            if (value > MaxShrink)
                value = MaxShrink;
            if (value == _scale)
                return;
            _scale = value;
            if (_container != null)
                _container.StretchShrink = _scale;
            UpdateRenderMode();
        }
    }

    // Moves user content (everything under the viewport/direct layer other
    // than the internal render camera) between the buffered SubViewport
    // path and the direct-render bypass, and shows/hides each path's
    // CanvasLayer to match - so a hidden, content-less SubViewport does no
    // extra rendering work while direct-render mode is active.
    private void UpdateRenderMode()
    {
        // Not ready yet - nothing to move, and UpdateRenderMode() runs
        // again at the end of _Ready() once there is.
        if (_viewport == null)
            return;

        var from = IsDirectRender ? (Node)_viewport : _directLayer;
        var to = IsDirectRender ? (Node)_directLayer : _viewport;

        foreach (Node child in from.GetChildren())
        {
            if (child == _renderCamera)
                continue;

            // keepGlobalTransform:false - the two parents live in different
            // viewports (different resolutions), so anchor-based sizing
            // (e.g. FullRect) should re-resolve fresh against the new
            // parent rather than carry over a compensating transform.
            child.Reparent(to, false);
        }

        _bufferedLayer.Visible = !IsDirectRender;
        _directLayer.Visible = IsDirectRender;
    }
}
