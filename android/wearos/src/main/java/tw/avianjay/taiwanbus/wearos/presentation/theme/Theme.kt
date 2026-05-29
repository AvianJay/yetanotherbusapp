package tw.avianjay.taiwanbus.wearos.presentation.theme

import androidx.compose.runtime.Composable
import androidx.wear.compose.material3.MaterialTheme

@Composable
fun AndroidTheme(
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        content = content,
    )
}
