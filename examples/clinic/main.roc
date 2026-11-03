# The functions that `examples/main.roc` shares with `tests/RefactoredTest.roc`.
# A package of its own, so that both apps import the one `Clinic.roc`.
package [Clinic] { surreal: "../../src/main.roc" }
