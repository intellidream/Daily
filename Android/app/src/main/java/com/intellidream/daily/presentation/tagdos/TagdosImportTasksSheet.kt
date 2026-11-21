package com.intellidream.daily.presentation.tagdos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.CheckBox
import androidx.compose.material.icons.rounded.CheckBoxOutlineBlank
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.intellidream.daily.database.TagdosRepository
import com.intellidream.daily.designsystem.ThemeColors
import com.intellidream.daily.model.TagdosParser
import com.intellidream.daily.network.ExternalTaskAccount
import com.intellidream.daily.network.ExternalTaskList
import com.intellidream.daily.network.ExternalTaskProvider
import com.intellidream.daily.network.ExternalTasksAuthException
import com.intellidream.daily.network.TagdosExternalTasksService
import kotlinx.coroutines.launch

private data class AndroidImportDraft(
    val id: String,
    val originalTitle: String,
    val originalNotes: String?,
    val isHighImportance: Boolean,
    val isAlreadyDsl: Boolean,
    val editedTag: String,
    val isSelected: Boolean = true
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagdosImportTasksSheet(
    repository: TagdosRepository,
    initialStreamId: String?,
    onImported: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val streams by repository.streams.collectAsState()
    val allAccounts by TagdosExternalTasksService.accounts.collectAsState()
    val isLoadingAccounts by TagdosExternalTasksService.isLoadingAccounts.collectAsState()

    var selectedProvider by remember { mutableStateOf(ExternalTaskProvider.MicrosoftToDo) }
    var selectedAccountId by remember { mutableStateOf<String?>(null) }
    var taskLists by remember { mutableStateOf<List<ExternalTaskList>>(emptyList()) }
    var selectedListId by remember { mutableStateOf<String?>(null) }
    val drafts = remember { mutableStateListOf<AndroidImportDraft>() }

    var isAuthenticating by remember { mutableStateOf(false) }
    var isLoadingLists by remember { mutableStateOf(false) }
    var isLoadingTasks by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var needsReauth by remember { mutableStateOf(false) }

    var destinationMode by remember { mutableStateOf("append") } // "append", "replace", "new"
    var targetStreamId by remember { mutableStateOf(initialStreamId ?: streams.firstOrNull()?.id) }
    var newStreamTitle by remember { mutableStateOf("") }

    val providerAccounts = remember(allAccounts, selectedProvider) {
        allAccounts.filter { it.provider == selectedProvider }
    }
    val selectedAccount = remember(providerAccounts, selectedAccountId) {
        providerAccounts.firstOrNull { it.id == selectedAccountId } ?: providerAccounts.firstOrNull()
    }
    val selectedList = remember(taskLists, selectedListId) {
        taskLists.firstOrNull { it.id == selectedListId }
    }

    suspend fun loadTasks(account: ExternalTaskAccount, listId: String) {
        isLoadingTasks = true
        errorMessage = null
        needsReauth = false
        try {
            val items = TagdosExternalTasksService.fetchTasks(account, listId)
            drafts.clear()
            items.forEach { item ->
                val (tagOrDsl, isDsl, _) = TagdosParser.prepareImportItem(
                    title = item.title,
                    notes = item.notes,
                    isHighImportance = item.isHighImportance
                )
                drafts.add(
                    AndroidImportDraft(
                        id = item.id,
                        originalTitle = item.title,
                        originalNotes = item.notes,
                        isHighImportance = item.isHighImportance,
                        isAlreadyDsl = isDsl,
                        editedTag = tagOrDsl
                    )
                )
            }
        } catch (e: ExternalTasksAuthException) {
            errorMessage = e.message
            needsReauth = e.needsReauth
        } catch (e: Exception) {
            errorMessage = e.message ?: "Failed to load tasks."
        } finally {
            isLoadingTasks = false
        }
    }

    suspend fun loadLists(account: ExternalTaskAccount) {
        isLoadingLists = true
        errorMessage = null
        needsReauth = false
        drafts.clear()
        try {
            val lists = TagdosExternalTasksService.fetchTaskLists(account)
            taskLists = lists
            val def = lists.firstOrNull { it.isDefault } ?: lists.firstOrNull()
            selectedListId = def?.id
            if (def != null) {
                if (newStreamTitle.isBlank()) newStreamTitle = def.title
                loadTasks(account, def.id)
            }
        } catch (e: ExternalTasksAuthException) {
            errorMessage = e.message
            needsReauth = e.needsReauth
        } catch (e: Exception) {
            errorMessage = e.message ?: "Failed to load lists."
        } finally {
            isLoadingLists = false
        }
    }

    fun launchSignIn() {
        scope.launch {
            isAuthenticating = true
            errorMessage = null
            needsReauth = false
            try {
                val acc = TagdosExternalTasksService.signIn(context, selectedProvider)
                selectedAccountId = acc.id
                loadLists(acc)
            } catch (e: Exception) {
                errorMessage = e.message ?: "Sign-in failed."
            } finally {
                isAuthenticating = false
            }
        }
    }

    LaunchedEffect(Unit) {
        if (targetStreamId == null) targetStreamId = streams.firstOrNull()?.id
        TagdosExternalTasksService.refreshAvailableAccounts()
        val accountsNow = TagdosExternalTasksService.accounts.value
        val currentAcc = accountsNow.firstOrNull { it.provider == selectedProvider } ?: accountsNow.firstOrNull()
        if (currentAcc != null) {
            selectedProvider = currentAcc.provider
            selectedAccountId = currentAcc.id
            loadLists(currentAcc)
        }
    }

    val selectedCount = drafts.count { it.isSelected && it.editedTag.isNotBlank() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF060E1E),
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.92f)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel", color = Color.White.copy(alpha = 0.7f))
                }
                Text(
                    text = "Import Tasks",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Button(
                    onClick = {
                        val chosen = drafts.filter { it.isSelected && it.editedTag.isNotBlank() }
                        if (chosen.isNotEmpty()) {
                            val dslChunks = mutableListOf<String>()
                            val memoLines = mutableListOf<String>()
                            for (item in chosen) {
                                val tag = item.editedTag.trim()
                                dslChunks.add(tag)
                                val notes = item.originalNotes?.trim().orEmpty()
                                if (item.isAlreadyDsl) {
                                    if (notes.isNotEmpty()) memoLines.add("• [$tag] $notes")
                                } else {
                                    memoLines.add(
                                        if (notes.isEmpty()) "• [$tag] ${item.originalTitle}"
                                        else "• [$tag] ${item.originalTitle} — $notes"
                                    )
                                }
                            }
                            val resultId = repository.importExternalTasks(
                                mode = destinationMode,
                                targetStreamId = targetStreamId,
                                newStreamTitle = newStreamTitle,
                                rawDslChunks = dslChunks,
                                memoLines = memoLines
                            )
                            onImported(resultId)
                            onDismiss()
                        }
                    },
                    enabled = selectedCount > 0,
                    colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                    shape = CircleShape
                ) {
                    Text(
                        text = "Import ($selectedCount)",
                        color = Color.Black,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp
                    )
                }
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Provider Switcher
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ExternalTaskProvider.entries.forEach { provider ->
                        val isSelected = selectedProvider == provider
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .background(
                                    if (isSelected) ThemeColors.accentPurple.copy(alpha = 0.38f)
                                    else Color.White.copy(alpha = 0.06f)
                                )
                                .border(
                                    1.dp,
                                    if (isSelected) ThemeColors.accentPurple else Color.White.copy(alpha = 0.12f),
                                    RoundedCornerShape(12.dp)
                                )
                                .clickable {
                                    selectedProvider = provider
                                    errorMessage = null
                                    needsReauth = false
                                    taskLists = emptyList()
                                    selectedListId = null
                                    drafts.clear()
                                    val nextAcc = allAccounts.firstOrNull { it.provider == provider }
                                    selectedAccountId = nextAcc?.id
                                    if (nextAcc != null) {
                                        scope.launch { loadLists(nextAcc) }
                                    }
                                }
                                .padding(vertical = 11.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = provider.displayName,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White else Color.White.copy(alpha = 0.65f)
                            )
                        }
                    }
                }

                // Account Section
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "ACCOUNT",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.5f)
                    )
                    if (providerAccounts.isNotEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier.clickable { launchSignIn() }
                        ) {
                            Icon(Icons.Rounded.AddCircle, null, tint = ThemeColors.accentCyan, modifier = Modifier.size(13.dp))
                            Text("Add Account", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = ThemeColors.accentCyan)
                        }
                    }
                }

                if (isLoadingAccounts) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), color = ThemeColors.accentCyan, strokeWidth = 2.dp)
                        Text("Checking connected accounts...", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
                    }
                } else if (providerAccounts.isEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.05f))
                            .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(14.dp))
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = "Connect your ${selectedProvider.displayName} account to browse lists and import tasks into TagDoS.",
                            fontSize = 12.sp,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                        Button(
                            onClick = { launchSignIn() },
                            enabled = !isAuthenticating,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text(
                                text = if (isAuthenticating) "Waiting for Browser..." else "Sign in with ${selectedProvider.displayName}",
                                color = Color.Black,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                } else {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        providerAccounts.forEach { acc ->
                            val isSelected = selectedAccount?.id == acc.id
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(if (isSelected) ThemeColors.accentCyan.copy(alpha = 0.2f) else Color.White.copy(alpha = 0.06f))
                                    .border(1.dp, if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.12f), CircleShape)
                                    .clickable {
                                        selectedAccountId = acc.id
                                        scope.launch { loadLists(acc) }
                                    }
                                    .padding(horizontal = 10.dp, vertical = 7.dp)
                            ) {
                                Icon(
                                    imageVector = if (isSelected) Icons.Rounded.CheckCircle else Icons.Rounded.Person,
                                    contentDescription = null,
                                    tint = if (isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.5f),
                                    modifier = Modifier.size(13.dp)
                                )
                                Text(acc.email, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                            }
                        }
                    }
                }

                errorMessage?.let { err ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(ThemeColors.accentPink.copy(alpha = 0.12f))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(err, fontSize = 11.5.sp, color = ThemeColors.accentPink)
                        if (needsReauth) {
                            Button(
                                onClick = { launchSignIn() },
                                colors = ButtonDefaults.buttonColors(containerColor = ThemeColors.accentCyan),
                                shape = CircleShape
                            ) {
                                Text("Re-authenticate & Grant Tasks Access", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 11.5.sp)
                            }
                        }
                    }
                }

                // Lists & Tasks
                if (selectedAccount != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("LISTS & TASKS", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.5f))
                        IconButton(onClick = { scope.launch { loadLists(selectedAccount) } }, modifier = Modifier.size(24.dp)) {
                            Icon(Icons.Rounded.Refresh, "Refresh", tint = ThemeColors.accentCyan, modifier = Modifier.size(15.dp))
                        }
                    }

                    if (isLoadingLists) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), color = ThemeColors.accentCyan, strokeWidth = 2.dp)
                            Text("Loading task lists...", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
                        }
                    } else if (taskLists.isNotEmpty()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            taskLists.forEach { list ->
                                val isSel = selectedListId == list.id
                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(if (isSel) ThemeColors.accentCyan else Color.White.copy(alpha = 0.08f))
                                        .clickable {
                                            selectedListId = list.id
                                            if (newStreamTitle.isBlank() || taskLists.any { it.title == newStreamTitle }) {
                                                newStreamTitle = list.title
                                            }
                                            scope.launch { loadTasks(selectedAccount, list.id) }
                                        }
                                        .padding(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text(
                                        text = list.title,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (isSel) Color.Black else Color.White
                                    )
                                }
                            }
                        }

                        if (isLoadingTasks) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp), color = ThemeColors.accentCyan, strokeWidth = 2.dp)
                                Text("Fetching active tasks...", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f))
                            }
                        } else if (drafts.isEmpty()) {
                            Text("No active tasks in this list.", fontSize = 12.sp, color = Color.White.copy(alpha = 0.5f))
                        } else {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("${drafts.size} active tasks", fontSize = 11.sp, color = Color.White.copy(alpha = 0.6f))
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(
                                        text = "Select All",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = ThemeColors.accentCyan,
                                        modifier = Modifier.clickable {
                                            for (i in drafts.indices) drafts[i] = drafts[i].copy(isSelected = true)
                                        }
                                    )
                                    Text(
                                        text = "Clear",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White.copy(alpha = 0.6f),
                                        modifier = Modifier.clickable {
                                            for (i in drafts.indices) drafts[i] = drafts[i].copy(isSelected = false)
                                        }
                                    )
                                }
                            }

                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                drafts.forEachIndexed { index, draft ->
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(Color.White.copy(alpha = if (draft.isSelected) 0.055f else 0.025f))
                                            .border(1.dp, Color.White.copy(alpha = 0.09f), RoundedCornerShape(12.dp))
                                            .padding(10.dp),
                                        verticalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            Icon(
                                                imageVector = if (draft.isSelected) Icons.Rounded.CheckBox else Icons.Rounded.CheckBoxOutlineBlank,
                                                contentDescription = null,
                                                tint = if (draft.isSelected) ThemeColors.accentCyan else Color.White.copy(alpha = 0.4f),
                                                modifier = Modifier
                                                    .size(20.dp)
                                                    .clickable { drafts[index] = draft.copy(isSelected = !draft.isSelected) }
                                            )

                                            OutlinedTextField(
                                                value = draft.editedTag,
                                                onValueChange = { drafts[index] = draft.copy(editedTag = it) },
                                                singleLine = true,
                                                modifier = Modifier.weight(1f),
                                                textStyle = TextStyle(
                                                    fontFamily = FontFamily.Monospace,
                                                    fontSize = 12.5.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    color = Color.White
                                                ),
                                                colors = OutlinedTextFieldDefaults.colors(
                                                    focusedBorderColor = ThemeColors.accentCyan,
                                                    unfocusedBorderColor = Color.White.copy(alpha = 0.14f)
                                                ),
                                                shape = RoundedCornerShape(8.dp)
                                            )

                                            Box(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background((if (draft.isAlreadyDsl) ThemeColors.accentCyan else ThemeColors.accentOrange).copy(alpha = 0.15f))
                                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                                            ) {
                                                Text(
                                                    text = if (draft.isAlreadyDsl) "DSL" else "AUTO + MEMO",
                                                    fontSize = 9.sp,
                                                    fontWeight = FontWeight.Black,
                                                    color = if (draft.isAlreadyDsl) ThemeColors.accentCyan else ThemeColors.accentOrange
                                                )
                                            }
                                        }

                                        if (!draft.isAlreadyDsl) {
                                            Text(
                                                text = draft.originalTitle,
                                                fontSize = 11.sp,
                                                color = Color.White.copy(alpha = 0.65f),
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.padding(start = 28.dp)
                                            )
                                        }
                                        draft.originalNotes?.takeIf { it.isNotBlank() }?.let { notes ->
                                            Text(
                                                text = notes,
                                                fontSize = 10.5.sp,
                                                color = Color.White.copy(alpha = 0.45f),
                                                maxLines = 2,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.padding(start = 28.dp)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Destination Section
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.04f))
                            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text("DESTINATION", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.5f))

                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf("append" to "Append", "replace" to "Replace", "new" to "New Stream").forEach { (key, label) ->
                                val isSel = destinationMode == key
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(if (isSel) ThemeColors.accentCyan else Color.White.copy(alpha = 0.08f))
                                        .clickable {
                                            destinationMode = key
                                            if (key == "new" && newStreamTitle.isBlank()) {
                                                newStreamTitle = selectedList?.title ?: "Imported Stream"
                                            }
                                        }
                                        .padding(vertical = 8.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = label,
                                        fontSize = 11.5.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (isSel) Color.Black else Color.White
                                    )
                                }
                            }
                        }

                        if (destinationMode == "new") {
                            OutlinedTextField(
                                value = newStreamTitle,
                                onValueChange = { newStreamTitle = it },
                                label = { Text("New Stream Title") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedTextColor = Color.White,
                                    unfocusedTextColor = Color.White,
                                    focusedBorderColor = ThemeColors.accentCyan,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                                    focusedLabelColor = ThemeColors.accentCyan,
                                    unfocusedLabelColor = Color.White.copy(alpha = 0.6f)
                                ),
                                shape = RoundedCornerShape(10.dp)
                            )
                        } else {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                streams.forEach { stream ->
                                    val isTarget = targetStreamId == stream.id
                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(if (isTarget) ThemeColors.accentPurple.copy(alpha = 0.45f) else Color.White.copy(alpha = 0.06f))
                                            .border(1.dp, if (isTarget) ThemeColors.accentPurple else Color.White.copy(alpha = 0.12f), CircleShape)
                                            .clickable { targetStreamId = stream.id }
                                            .padding(horizontal = 10.dp, vertical = 7.dp)
                                    ) {
                                        Text(
                                            text = "S${stream.orderIndex + 1}: ${stream.displayTitle}",
                                            fontSize = 11.5.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = if (isTarget) Color.White else Color.White.copy(alpha = 0.7f),
                                            maxLines = 1
                                        )
                                    }
                                }
                            }

                            if (destinationMode == "replace") {
                                Text(
                                    text = "Warning: Existing pills and active memos in the selected stream will be replaced.",
                                    fontSize = 11.sp,
                                    color = ThemeColors.accentOrange
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}
