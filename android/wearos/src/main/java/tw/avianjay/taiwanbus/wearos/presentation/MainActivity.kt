package tw.avianjay.taiwanbus.wearos.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.EdgeButton
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import tw.avianjay.taiwanbus.wearos.data.FavoriteStop
import tw.avianjay.taiwanbus.wearos.data.RouteSearchResult
import tw.avianjay.taiwanbus.wearos.data.WearDataRepository
import tw.avianjay.taiwanbus.wearos.data.WearHomeState
import tw.avianjay.taiwanbus.wearos.data.WearNodeMessenger
import tw.avianjay.taiwanbus.wearos.presentation.theme.AndroidTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WearDataRepository.ensureLoaded(applicationContext)
        setContent {
            AndroidTheme {
                WearApp(
                    state = WearDataRepository.state,
                    onRefresh = {
                        WearDataRepository.refresh(applicationContext)
                        WearNodeMessenger.requestRefresh(applicationContext)
                    },
                    onSearch = WearDataRepository::searchRoutes,
                )
            }
        }
    }
}

private enum class WearScreen {
    Favorites,
    Search,
}

@Composable
private fun WearApp(
    state: WearHomeState,
    onRefresh: () -> Unit,
    onSearch: (String) -> List<RouteSearchResult>,
) {
    var screen by rememberSaveable { mutableStateOf(WearScreen.Favorites) }
    var query by rememberSaveable { mutableStateOf("") }
    val searchResults = remember(query) { onSearch(query) }

    AppScaffold {
        val listState = rememberTransformingLazyColumnState()
        val transformationSpec = rememberTransformationSpec()

        ScreenScaffold(
            scrollState = listState,
            edgeButton = {
                EdgeButton(
                    onClick = {
                        if (screen == WearScreen.Search) {
                            screen = WearScreen.Favorites
                        } else {
                            onRefresh()
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    ),
                ) {
                    Text(if (screen == WearScreen.Search) "Back" else "Refresh")
                }
            },
        ) { contentPadding ->
            TransformingLazyColumn(contentPadding = contentPadding, state = listState) {
                item {
                    ListHeader(
                        modifier =
                            Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                        transformation = SurfaceTransformation(transformationSpec),
                    ) {
                        Column {
                            Text(
                                if (screen == WearScreen.Favorites) {
                                    "My favorites"
                                } else {
                                    "Route search"
                                },
                            )
                            Text(
                                when {
                                    screen == WearScreen.Search ->
                                        "Mock results ready for future API wiring"

                                    state.settings.syncEnabled && state.hasSyncedFavorites ->
                                        "Watch favorites synced from phone"

                                    state.settings.syncEnabled ->
                                        "No favorites selected for Wear OS yet"

                                    else ->
                                        "Turn on Wear OS sync in the phone app"
                                },
                            )
                        }
                    }
                }

                when (screen) {
                    WearScreen.Favorites -> {
                        favoritesContent(
                            state = state,
                            onOpenSearch = { screen = WearScreen.Search },
                        )
                    }

                    WearScreen.Search -> {
                        searchContent(
                            query = query,
                            results = searchResults,
                            onQueryChange = { query = it },
                            onUseRoute = { query = it.routeName },
                        )
                    }
                }
            }
        }
    }
}

private fun androidx.wear.compose.foundation.lazy.TransformingLazyColumnScope.favoritesContent(
    state: WearHomeState,
    onOpenSearch: () -> Unit,
) {
    if (!state.settings.syncEnabled || state.favorites.isEmpty()) {
        item {
            Button(
                onClick = onOpenSearch,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
            ) {
                Column {
                    Text("Search routes")
                    Text("Try mock route results while favorites are empty")
                }
            }
        }
        item {
            WearInfoCard(
                title = if (state.settings.syncEnabled) {
                    "No synced favorites"
                } else {
                    "Sync is off"
                },
                subtitle = if (state.settings.syncEnabled) {
                    "Pick favorites in the phone app and sync again."
                } else {
                    "Open YABus on Android and enable Wear OS sync."
                },
            )
        }
        return
    }

    item {
        Button(
            onClick = onOpenSearch,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column {
                Text("Search routes")
                Text("Mock search results for the first Wear build")
            }
        }
    }

    state.favorites.forEach { favorite ->
        item {
            FavoriteArrivalCard(
                favorite = favorite,
                state = state,
            )
        }
    }

    state.lastRefreshAtMs?.let { refreshedAtMs ->
        item {
            WearInfoCard(
                title = "Last refresh",
                subtitle = formatClockTime(refreshedAtMs),
            )
        }
    }
}

private fun androidx.wear.compose.foundation.lazy.TransformingLazyColumnScope.searchContent(
    query: String,
    results: List<RouteSearchResult>,
    onQueryChange: (String) -> Unit,
    onUseRoute: (RouteSearchResult) -> Unit,
) {
    item {
        SearchBox(
            value = query,
            onValueChange = onQueryChange,
        )
    }

    if (results.isEmpty()) {
        item {
            WearInfoCard(
                title = "No mock matches",
                subtitle = "Try 307, 605, 965, R26 or Blue 15.",
            )
        }
        return
    }

    results.forEach { route ->
        item {
            Button(
                onClick = { onUseRoute(route) },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                ),
            ) {
                Column {
                    Text(route.routeName)
                    Text(route.description)
                    Text(route.provider)
                }
            }
        }
    }
}

@Composable
private fun FavoriteArrivalCard(
    favorite: FavoriteStop,
    state: WearHomeState,
) {
    val arrival = state.arrivalFor(favorite.id)
    Button(
        onClick = {},
        modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                ),
            ) {
        Column {
            Text(favorite.displayRouteName)
            Text(favorite.displayStopName)
            Text(arrival?.etaText ?: "Mock arrival unavailable")
            Text(favorite.groupName.ifBlank { favorite.provider })
        }
    }
}

@Composable
private fun WearInfoCard(
    title: String,
    subtitle: String,
) {
    Button(
        onClick = {},
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
    ) {
        Column {
            Text(title)
            Text(subtitle)
        }
    }
}

@Composable
private fun SearchBox(
    value: String,
    onValueChange: (String) -> Unit,
) {
    val textStyle = TextStyle(
        color = MaterialTheme.colorScheme.onSurface,
    )
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        textStyle = textStyle,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.Characters,
            imeAction = ImeAction.Search,
        ),
        decorationBox = { innerTextField ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        shape = RoundedCornerShape(20.dp),
                    )
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                if (value.isEmpty()) {
                    Text("307 / 605 / R26 / airport")
                }
                innerTextField()
            }
        },
    )
}

private fun formatClockTime(timestampMs: Long): String {
    val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
    return formatter.format(Date(timestampMs))
}
