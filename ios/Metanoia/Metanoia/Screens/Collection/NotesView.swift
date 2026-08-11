import SwiftUI

struct NotesView: View {
    @State private var notes: [Note] = []
    @State private var selectedNote: Note?
    @State private var showingAddNote = false
    
    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Notes Yet",
                    systemImage: "note.text",
                    description: Text("Add notes while reading to remember your insights.")
                )
            } else {
                List {
                    ForEach(notes) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            NoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteNotes)
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddNote = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
        .sheet(isPresented: $showingAddNote) {
            AddNoteView { newNote in
                notes.append(newNote)
                saveNotes()
            }
        }
        .onAppear(perform: loadNotes)
    }
    
    private func deleteNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        saveNotes()
    }
    
    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: "verseNotes")
    }
    
    private func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: "verseNotes"),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
    }
}

private struct NoteRow: View {
    let note: Note
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "book.closed")
                    .foregroundStyle(.blue)
                Text("\(note.book) \(note.chapter):\(note.verse)")
                    .font(.headline)
                Spacer()
                Text(note.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(note.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct NoteDetailView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(note.book) \(note.chapter):\(note.verse)")
                        .font(.title2.bold())
                    Text(note.content)
                        .font(.body)
                    Text("Last updated \(note.timestamp.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var book = ""
    @State private var chapter = ""
    @State private var verse = ""
    @State private var content = ""
    
    let onSave: (Note) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Verse Reference") {
                    TextField("Book", text: $book)
                    TextField("Chapter", text: $chapter)
                        .keyboardType(.numberPad)
                    TextField("Verse", text: $verse)
                        .keyboardType(.numberPad)
                }
                Section("Note") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let note = Note(
                            id: Int64(Date().timeIntervalSince1970),
                            book: book,
                            chapter: Int(chapter) ?? 1,
                            verse: Int(verse) ?? 1,
                            content: content,
                            timestamp: .now
                        )
                        onSave(note)
                        dismiss()
                    }
                    .disabled(book.isEmpty || content.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NotesView()
}
