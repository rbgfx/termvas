# Terminal input

`Termvas::InputParser` emits `key_press` events. Printable bytes include a
`char`; Ctrl-C emits `key: :close`. CSI and SS3 arrows, Home/End, Insert,
Delete, Page Up/Down, F1-F4, and SGR mouse events are supported.

CSI modifier parameters and SGR mouse modifier bits become `:shift`, `:alt`,
and `:control`. SGR wheel events become `scroll` events with `dx` and `dy`;
the parser reports one logical wheel step per terminal event. Terminals do not
report key release events, so Termvas emits presses only.
