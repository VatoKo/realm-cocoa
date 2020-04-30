////////////////////////////////////////////////////////////////////////////
//
// Copyright 2020 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import Combine
import SwiftUI
import RealmSwift

struct RecipeRow: View {
    var recipe: Recipe
    @EnvironmentObject var state: ContentViewState

    init(_ recipe: Recipe) {
        self.recipe = recipe
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(recipe.name).onTapGesture {
                    self.state.sectionState[self.recipe] = !self.isExpanded(self.recipe)
                }.animation(.interactiveSpring())
                if self.isExpanded(recipe) {
                    ForEach(recipe.ingredients) { ingredient in
                        HStack {
                            URLImage(ingredient.foodType!.imgUrl)
                            Text(ingredient.name!)
                        }.padding(.leading, 5)
                    }.animation(.interactiveSpring())
                }
            }
            Spacer()
        }
    }

    private func isExpanded(_ section: Recipe) -> Bool {
        self.state.sectionState[section] ?? false
    }
}

final class ContentViewState: ObservableObject {
    /// This dict will allow us to store state on the expansion and contraction of rows.
    @Published var sectionState: [Recipe: Bool] = [:]
}

func foo() {

}

class DownloadProgress: Object {
    @objc dynamic var bytesWritten: Int64 = 0
}

class ProgressTrackingDelegate: NSObject, URLSessionDownloadDelegate {
    public let queue = DispatchQueue(label: "background queue")
    private var realm: Realm!

    override init() {
        super.init()
        queue.sync { realm = try! Realm(queue: queue) }
    }

    public var operationQueue: OperationQueue {
        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = queue
        return operationQueue
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let url = downloadTask.originalRequest?.url?.absoluteString else { return }
        try! realm.write {
            let progress = realm.object(ofType: DownloadProgress.self, forPrimaryKey: url)
            if let progress = progress {
                progress.bytesWritten = totalBytesWritten
            } else {
                realm.create(DownloadProgress.self, value: [
                    "url": url,
                    "bytesWritten": bytesWritten
                ])
            }
        }
    }
}
let delegate = ProgressTrackingDelegate()
let session = URLSession(configuration: URLSessionConfiguration.default,
                         delegate: delegate,
                         delegateQueue: delegate.operationQueue)

func setup() {
}

class Dog: Object, ObjectKeyIdentifable {
    
    @objc dynamic var name: String = ""
    @objc dynamic var age: Int = 0
}

struct DogGroup {
    let label: String
    let dogs: [Dog]
}

final class DogSource: ObservableObject {
    @Published var groups: [DogGroup] = []

    private var cancellable: AnyCancellable?
    init() {
        cancellable = try! Realm().objects(Dog.self)
            .publisher
            .subscribe(on: DispatchQueue(label: "background queue"))
            .freeze()
            .map { (dogs: Results<Dog>) -> [DogGroup] in
                Dictionary(grouping: dogs, by: { $0.age })
                    .map { DogGroup(label: "\($0)", dogs: $1) }
                    .sorted(by: { $0.label < $1.label })
            }
            .receive(on: DispatchQueue.main)
            .assertNoFailure()
            .assign(to: \.groups, on: self)
    }
    deinit {
        cancellable?.cancel()
    }
}

struct DogList: View {
    @ObservedObject var dogs: RealmSwift.List<Dog>

    var body: some View {
        List {
            ForEach(dogs) { dog in
                Text(dog.name)
            }
        }
    }
}

struct ContentView: View {
    @State private var searchTerm: String = ""
    @State private var showRecipeFormView = false
    @ObservedObject var state = ContentViewState()
    @ObservedObject var recipes: RealmSwift.List<Recipe>

    var body: some View {
        NavigationView {
            List {
                Section(header:
                    HStack {
                        SearchBar(text: self.$searchTerm)
                            .frame(width: 300, alignment: .leading)
                            .padding(5)
                        NavigationLink(destination: RecipeFormView(recipes: self.recipes, showRecipeFormView: self.$showRecipeFormView),
                                       isActive: self.$showRecipeFormView,
                                       label: {
                                        Button("add recipe") {
                                            self.showRecipeFormView = true
                                        }
                        })
                }) {
                    ForEach(filteredCollection().freeze()) { recipe in
                        RecipeRow(recipe).environmentObject(self.state)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
            }.listStyle(GroupedListStyle())
                .navigationBarTitle("recipes", displayMode: .large)
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(false)
                .navigationBarItems(trailing: EditButton())
        }
    }

    func filteredCollection() -> AnyRealmCollection<Recipe> {
        if self.searchTerm.isEmpty {
            return AnyRealmCollection(self.recipes)
        } else {
            return AnyRealmCollection(self.recipes.filter("name CONTAINS[c] %@", searchTerm))
        }
    }

    func delete(at offsets: IndexSet) {
        if let realm = recipes.realm {
            try! realm.write {
                realm.delete(recipes[offsets.first!])
            }
        } else {
            recipes.remove(at: offsets.first!)
        }
    }

    func move(fromOffsets offsets: IndexSet, toOffset to: Int) {
        recipes.realm?.beginWrite()
        recipes.move(fromOffsets: offsets, toOffset: to)
        try! recipes.realm?.commitWrite()
    }
}

#if DEBUG
struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        return ContentView(recipes: .init())
    }
}
#endif
