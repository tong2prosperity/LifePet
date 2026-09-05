/// Platform gesture gate for the Home-stage pat interaction.
///
/// Core still owns what a successful pat says and whether it is cooling down;
/// the scene only decides when a physical gesture becomes one pat command.
typealias HomePatGesturePolicy = PiboPatGesturePolicy
