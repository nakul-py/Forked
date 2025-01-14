import SwiftUI

struct ForkerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    
    let existingForkerId: Forker.ID?
    var forkerIsNew: Bool { existingForkerId == nil }
            
    @State private var editedForker: Forker = Forker()
    @State private var isEditing = false
    @State private var hasAppeared = false
    
    private var canSave: Bool {
        !editedForker.firstName.isEmpty || !editedForker.lastName.isEmpty
    }
    
    private func resetEditedForker() {
        if let existingForkerId {
            store.prepareToEditForker()
            editedForker = store.editingForker(withId: existingForkerId)!
        } else {
            editedForker = Forker()
        }
    }
    
    var body: some View {
        Form {
            Section("Basic Info") {
                if isEditing {
                    TextField("First Name", text: $editedForker.firstName)
                    TextField("Last Name", text: $editedForker.lastName)
                    TextField("Company", text: $editedForker.company)
                    TextField("Email", text: $editedForker.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("First Name", value: editedForker.firstName)
                    LabeledContent("Last Name", value: editedForker.lastName)
                    if !editedForker.company.isEmpty {
                        LabeledContent("Company", value: editedForker.company)
                    }
                    if !editedForker.email.isEmpty {
                        LabeledContent("Email", value: editedForker.email)
                    }
                }
            }
            
            Section("Additional Info") {
                if isEditing {
                    DatePicker(
                        "Birthday",
                        selection: Binding(
                            get: { editedForker.birthday ?? Date() },
                            set: { editedForker.birthday = $0 }
                        ),
                        displayedComponents: .date
                    )
                    
                    LabeledContent("Owes Me") {
                        TextField("Amount", value: $editedForker.balance.dollarAmount, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Category", selection: $editedForker.category) {
                        Text("None")
                            .tag(Optional<ForkerCategory>.none)
                        ForEach(ForkerCategory.allCases, id: \.self) { category in
                            Label(category.rawValue.capitalized, systemImage: category.systemImage)
                                .tag(Optional(category))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    
                    Picker("Color", selection: $editedForker.color) {
                        Text("None")
                            .tag(Optional<ForkerColor>.none)
                        ForEach(ForkerColor.allCases, id: \.self) { color in
                            Label(color.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(color.color)
                                .tag(Optional(color))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    
                    TextField("Tags", text: Binding(
                        get: {
                            editedForker.tags.joined(separator: " ")
                        },
                        set: { newValue in
                            let tags = newValue.components(separatedBy: CharacterSet(charactersIn: "-_").union(.punctuationCharacters).symmetricDifference(.punctuationCharacters).union(.whitespaces))
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            editedForker.tags = Set(tags)
                        }
                    ))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    
                    TextField("Notes", text: $editedForker.notes, axis: .vertical)
                        .lineLimit(5...10)
                } else {
                    if let birthday = editedForker.birthday {
                        LabeledContent("Birthday") {
                            Text(birthday, style: .date)
                        }
                    }
                    
                    if editedForker.balance.dollarAmount != 0 {
                        LabeledContent("Owes Me") {
                            Text(editedForker.balance.dollarAmount, format: .currency(code: "USD"))
                                .foregroundStyle(editedForker.balance.dollarAmount < 0 ? .red : .green)
                        }
                    }
                    
                    if let category = editedForker.category {
                        LabeledContent("Category") {
                            Label(category.rawValue.capitalized, systemImage: category.systemImage)
                        }
                    }
                    
                    if let color = editedForker.color {
                        LabeledContent("Color") {
                            Label(color.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(color.color)
                        }
                    }
                    
                    if !editedForker.tags.isEmpty {
                        LabeledContent("Tags") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(editedForker.tags).sorted(), id: \.self) { tag in
                                        Text(tag)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.secondary.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                    
                    if !editedForker.notes.isEmpty {
                        LabeledContent("Notes", value: editedForker.notes)
                    }
                }
            }
        }
        .animation(.default, value: isEditing)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            resetEditedForker()
            isEditing = forkerIsNew
        }
        .navigationTitle(editedForker.firstName.isEmpty ? "New Forker" : "\(editedForker.firstName) \(editedForker.lastName)")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if forkerIsNew {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        store.addForker(editedForker)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            store.updateEditingForker(editedForker)
                            isEditing = false
                        }
                        .disabled(!canSave)
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
                
                if isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            resetEditedForker()
                            isEditing = false
                        }
                    }
                }
            }
        }
    }
} 
