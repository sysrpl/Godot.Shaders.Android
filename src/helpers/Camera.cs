using Godot;

namespace Codebot.Godot;

public enum CameraMode { ModeOrbit, ModeShooter };

// Reusable camera rig: a mouse-driven orbit camera that can toggle (F3) into
// a free-fly first-person camera. Add an instance as a child of your scene
// root and read the Camera property wherever you need the active Camera3D
// (e.g. to spawn projectiles along its view direction).
public partial class Camera : Node3D
{
    private Camera3D _camera;
    private Node3D _pivot;
    private CameraMode _mode;

    public Camera3D View => _camera;

    // Switches between the orbit camera and the free-fly first-person
    // camera. The camera itself never carries a collision shape, so moving
    // it directly (see _Process()) already clips through everything.
    public CameraMode Mode
    {
        get => _mode;
        set
        {
            if (_mode == value)
                return;
            _mode = value;
            if (_mode == CameraMode.ModeShooter)
            {
                // Detach from the orbit pivot so the camera can move freely,
                // preserving its current world transform as the seed for the
                // first-person look angles.
                var globalTransform = View.GlobalTransform;
                _pivot.RemoveChild(View);
                AddChild(View);
                _camera.GlobalTransform = globalTransform;
                _firstPersonYaw = _yaw;
                _firstPersonPitch = _pitch;
                Input.MouseMode = Input.MouseModeEnum.Captured;
            }
            else
            {
                // Reattach to the pivot and let UpdateCameraTransform() drive
                // the camera's transform again.
                RemoveChild(View);
                _pivot.AddChild(View);
                Input.MouseMode = Input.MouseModeEnum.Visible;
                UpdateCameraTransform();
            }
        }
    }

    // Orbit-camera state: yaw/pitch/distance are updated by mouse input and
    // converted into an actual transform by UpdateCameraTransform().
    private float _yaw = 0f;
    private float _pitch = -20f;
    private float _distance = 4f;
    private const float MinDistance = 1f;
    private const float MaxDistance = 15f;
    private const float RotateSpeed = 0.3f;
    private const float ZoomSpeed = 0.3f;

    private bool _dragging = false;

    // First-person free-fly camera state, used while _mode is ModeShooter.
    private float _firstPersonYaw = 0f;
    private float _firstPersonPitch = 0f;
    private const float FirstPersonMoveSpeed = 6f;

    public override void _Ready()
    {
        _mode = CameraMode.ModeOrbit;
        // Orbit rig: a pivot Node3D sits at the target point and the camera
        // is a child offset along +Z from it. Rotating the pivot orbits the
        // camera around the target; moving the camera along its local Z
        // zooms in/out. See UpdateCameraTransform() for the full math.
        _pivot = new Node3D
        {
            Position = new Vector3(0, 1f, 0)
        };
        AddChild(_pivot);
        _camera = new Camera3D();
        _pivot.AddChild(View);
        UpdateCameraTransform();
    }

    // Moves the camera when in first-person mode; call from the owning
    // scene's _Process().
    public override void _Process(double delta)
    {
        if (_mode != CameraMode.ModeShooter)
            return;

        var basis = View.GlobalTransform.Basis;
        var direction = Vector3.Zero;
        if (Input.IsKeyPressed(Key.W))
            direction -= basis.Z;
        if (Input.IsKeyPressed(Key.S))
            direction += basis.Z;
        if (Input.IsKeyPressed(Key.A))
            direction -= basis.X;
        if (Input.IsKeyPressed(Key.D))
            direction += basis.X;
        if (direction != Vector3.Zero)
            View.GlobalPosition += direction.Normalized() * FirstPersonMoveSpeed * (float)delta;
    }

    // Handles mouse-look/zoom for the orbit camera.
    public override void _UnhandledInput(InputEvent e)
    {
        if (e is InputEventMouseButton mouseButton)
        {
            if (mouseButton.ButtonIndex == MouseButton.Left)
                // Track left-button press/release so InputEventMouseMotion
                // below knows whether the user is currently dragging.
                _dragging = mouseButton.Pressed;
            else if (mouseButton.ButtonIndex == MouseButton.WheelUp && _mode == CameraMode.ModeOrbit)
            {
                _distance = Mathf.Clamp(_distance - ZoomSpeed, MinDistance, MaxDistance);
                UpdateCameraTransform();
            }
            else if (mouseButton.ButtonIndex == MouseButton.WheelDown && _mode == CameraMode.ModeOrbit)
            {
                _distance = Mathf.Clamp(_distance + ZoomSpeed, MinDistance, MaxDistance);
                UpdateCameraTransform();
            }
        }
        else if (e is InputEventMouseMotion mouseMotion && _mode == CameraMode.ModeShooter)
        {
            // Free mouse-look: no button needs to be held, since the mouse
            // is captured while in first-person mode.
            _firstPersonYaw -= mouseMotion.Relative.X * RotateSpeed;
            _firstPersonPitch -= mouseMotion.Relative.Y * RotateSpeed;
            _firstPersonPitch = Mathf.Clamp(_firstPersonPitch, -89f, 89f);
            _camera.Rotation = new Vector3(
                Mathf.DegToRad(_firstPersonPitch),
                Mathf.DegToRad(_firstPersonYaw),
                0f
            );
        }
        else if (e is InputEventMouseMotion mouseMotion2 && _dragging)
        {
            // While dragging, mouse movement rotates the orbit pivot:
            // horizontal movement changes yaw, vertical changes pitch.
            _yaw -= mouseMotion2.Relative.X * RotateSpeed;
            _pitch -= mouseMotion2.Relative.Y * RotateSpeed;
            _pitch = Mathf.Clamp(_pitch, -80f, 80f);
            UpdateCameraTransform();
        }
    }

    // Switches between the orbit camera and a free-fly first-person camera;
    // bound to F3 by the owning scene.
    public void ToggleCameraMode()
    {
        Mode = _mode == CameraMode.ModeOrbit ? CameraMode.ModeShooter : CameraMode.ModeOrbit;
    }

    // Applies the current yaw/pitch/distance orbit-camera state to the
    // actual scene transform: rotates the pivot, offsets the camera along
    // its local +Z by `distance`, then re-aims it at the pivot so it always
    // faces the target regardless of rotation.
    private void UpdateCameraTransform()
    {
        _pivot.Rotation = new Vector3(
            Mathf.DegToRad(_pitch),
            Mathf.DegToRad(_yaw),
            0f
        );
        _camera.Position = new Vector3(0, 0, _distance);
        _camera.LookAt(_pivot.GlobalPosition, Vector3.Up);
    }
}
