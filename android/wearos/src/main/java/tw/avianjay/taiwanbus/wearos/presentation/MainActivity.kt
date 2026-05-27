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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.TransformingLazyColumnScope
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
import kotlinx.coroutines.delay
import tw.avianjay.taiwanbus.wearos.data.FavoriteStop
import tw.avianjay.taiwanbus.wearos.data.RouteSearchResult
import tw.avianjay.taiwanbus.wearos.data.WearDataRepository
import tw.avianjay.taiwanbus.wearos.data.WearHomeState
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
                    },
                    onSearch = { query ->
                        WearDataRepository.searchRoutes(applicationContext, query)
                    },
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
    onSearch: suspend (String) -> List<RouteSearchResult>,
) {
    var screen by rememberSaveable { mutableStateOf(WearScreen.Favorites) }
    var query by rememberSaveable { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<RouteSearchResult>>(emptyList()) }
    var searchLoading by remember { mutableStateOf(false) }
    var searchError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(screen, query) {
        if (screen != WearScreen.Search) {
            searchLoading = false
            return@LaunchedEffect
        }

        val normalized = query.trim()
        if (normalized.isEmpty()) {
            searchResults = emptyList()
            searchLoading = false
            searchError = null
            return@LaunchedEffect
        }

        delay(250)
        searchLoading = true
        searchError = null
        runCatching {
            onSearch(normalized)
        }.onSuccess { results ->
            searchResults = results
            searchLoading = false
        }.onFailure { error ->
            searchResults = emptyList()
            searchLoading = false
            searchError = error.message ?: "Route search failed."
        }
    }

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
                                        "Search uses the live network API directly"

                                    state.settings.syncEnabled && state.hasSyncedFavorites ->
                                        "Favorites sync from phone, arrivals refresh from live API"

                                    state.settings.syncEnabled ->
                                        "No synced favorites yet. Search still works online."

                                    else ->
                                        "Turn on Wear OS sync in the phone app for favorites"
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
                            loading = searchLoading,
                            error = searchError,
                            onQueryChange = { query = it },
                            onUseRoute = { query = it.routeName },
                        )
                    }
                }
            }
        }
    }
}

private fun TransformingLazyColumnScope.favoritesContent(
    state: WearHomeState,
    onOpenSearch: () -> Unit,
) {
    item {
        Button(
            onClick = onOpenSearch,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column {
                Text("Search routes")
                Text("Live API search works even without a phone connection")
            }
        }
    }

    if (!state.settings.syncEnabled || state.favorites.isEmpty()) {
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

    if (state.isRefreshing) {
        item {
            WearInfoCard(
                title = "Refreshing",
                subtitle = "Loading live arrivals from the API...",
            )
        }
    }

    state.lastRefreshError?.let { error ->
        item {
            WearInfoCard(
                title = "Refresh failed",
                subtitle = error,
            )
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
                title = "Last update",
                subtitle = formatClockTime(refreshedAtMs),
            )
        }
    }
}

private fun TransformingLazyColumnScope.searchContent(
    query: String,
    results: List<RouteSearchResult>,
    loading: Boolean,
    error: String?,
    onQueryChange: (String) -> Unit,
    onUseRoute: (RouteSearchResult) -> Unit,
) {
    item {
        SearchBox(
            value = query,
            onValueChange = onQueryChange,
        )
    }

    if (query.trim().isEmpty()) {
        item {
            WearInfoCard(
                title = "Search live routes",
                subtitle = "Type a route number or keyword to query the API.",
            )
        }
        return
    }

    if (loading) {
        item {
            WearInfoCard(
                title = "Searching",
                subtitle = "Looking up live route data...",
            )
        }
        return
    }

    if (error != null) {
        item {
            WearInfoCard(
                title = "Search failed",
                subtitle = error,
            )
        }
        return
    }

    if (results.isEmpty()) {
        item {
            WearInfoCard(
                title = "No matches",
                subtitle = "No live routes matched this query.",
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
            Text(arrival?.etaText ?: "No realtime data")
            arrival?.arrivalEpochMs?.let { arrivalAtMs ->
                Text("At ${formatClockTime(arrivalAtMs)}")
            }
            Text(arrival?.statusText ?: favorite.groupName.ifBlank { favorite.provider })
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
                    Text("307 / airport / Taipei")
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
