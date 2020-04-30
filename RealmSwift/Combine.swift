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

#if canImport(Combine)
import Combine
import Realm.Private

// MARK: - Identifiable

/// A protocol which defines a default identity for Realm Objects
///
/// Declaraing your Object subclass as conforming to this protocol will supply a default implemention for `Identifiable`'s `id` which works for Realm Objects:
///
///     // Automatically conforms to `Identifiable`
///     class MyObjectType: Object, ObjectKeyIdentifiable {
///         // ...
///     }
public protocol ObjectKeyIdentifable: Identifiable, Object {
    /// The stable identity of the entity associated with `self`.
    var id: UInt64 { get }
}

extension ObjectKeyIdentifable {
    /// A stable identifier for this object. For managed Realm objects, this value will be the same for all object instances which refer to the same object (i.e. for which `Object.isSameObject(as:)` returns true).
    public var id: UInt64 {
        RLMObjectBaseGetCombineId(self)
    }
}

// MARK: - Combine

/// A type which can be passed to `publisher()` or `changesetPublisher()`.
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public protocol RealmSubscribable {
    func _observe<S>(on queue: DispatchQueue?, _ subscriber: S)
        -> NotificationToken where S: Subscriber, S.Input == Self, S.Failure == Error
    func _observe<S>(_ subscriber: S)
        -> NotificationToken where S: Subscriber, S.Input == Void, S.Failure == Never
}

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension Publisher {
    /// Freezes all Realm objects and collections from the upstream publisher
    ///
    /// Freezing a Realm object makes it no longer live-update when writes are made to the Realm and makes it safe to pass freely between threads.
    ///
    /// - Returns: A publisher that publishes frozen copies of the objects which the upstream publisher publishes.
    public func freeze<T>() -> Combine.Publishers.Map<Self, T> where Output: ThreadConfined, T == Output {
        return map { $0.freeze() }
    }

    /// Freezes all Realm object changesets from the upstream publisher.
    ///
    /// Freezing a Realm object changeset makes the included object reference no longer live-update when writes are made to the Realm and makes it safe to pass freely between threads.
    ///
    /// - Returns: A publisher that publishes frozen copies of the objects which the upstream publisher publishes.
    public func freeze<T: Object>() -> Combine.Publishers.Map<Self, ObjectChange<T>> where Output == ObjectChange<T> {
        return map {
            if case .change(let object, let properties) = $0 {
                return .change(object.freeze(), properties)
            }
            return $0
        }
    }

    /// Freezes all Realm collection changesets from the upstream publisher.
    ///
    /// Freezing a Realm collection changeset makes the included collection reference no longer live-update when writes are made to the Realm and makes it safe to pass freely between threads.
    ///
    /// - Returns: A publisher that publishes frozen copies of the objects which the upstream publisher publishes.
    public func freeze<T: RealmCollection>()
        -> Combine.Publishers.Map<Self, RealmCollectionChange<T>> where Output == RealmCollectionChange<T> {
            return map {
                switch $0 {
                case .initial(let collection):
                    return .initial(collection.freeze())
                case .update(let collection, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                    return .update(collection.freeze(), deletions: deletions, insertions: insertions, modifications: modifications)
                case .error(let error):
                    return .error(error)
                }
            }
    }
}

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension Publisher where Output: ThreadConfined {
    /// Enables passing thread-confined objects to a different dispatch queue.
    ///
    /// Each call to `receive(on:)` on a publisher which emits Realm thread-confined objects must be proceeded by a call to `.threadSafeReference()`.
    /// The returned publisher handles the required logic to pass the thread-confined object to the new queue.
    /// Only serial dispatch queues are supported and using other schedulers will result in a fatal error.
    ///
    /// For example, to subscribe on a background thread, do some work there, then pass the object to the main thread you can do:
    ///
    ///     let cancellable = publisher(myObject)
    ///         .subscribe(on: DispatchQueue(label: "background queue")
    ///         .print()
    ///         .threadSafeReference()
    ///         .receive(on: DispatchQueue.main)
    ///         .sink { object in
    ///             // Do things with the object on the main thread
    ///         }
    ///
    /// Calling this function on a publisher which emits frozen or unmanaged objects is unneccesary but is allowed.
    ///
    /// - Returns: A publisher that supports `receive(on:)` for thread-confined objects.
    public func threadSafeReference() -> Publishers.MakeThreadSafe<Self> {
        Publishers.MakeThreadSafe(self)
    }
}

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension Publisher {
    /// Enables passing object changesets to a different dispatch queue.
    ///
    /// Each call to `receive(on:)` on a publisher which emits Realm thread-confined objects must be proceeded by a call to `.threadSafeReference()`
    /// The returned publisher handles the required logic to pass the thread-confined object to the new queue.
    /// Only serial dispatch queues are supported and using other schedulers will result in a fatal error.
    ///
    /// For example, to subscribe on a background thread, do some work there, then pass the object changeset to the main thread you can do:
    ///
    ///     let cancellable = changesetPublisher(myObject)
    ///         .subscribe(on: DispatchQueue(label: "background queue")
    ///         .print()
    ///         .threadSafeReference()
    ///         .receive(on: DispatchQueue.main)
    ///         .sink { objectChange in
    ///             // Do things with the object on the main thread
    ///         }
    ///
    /// - Returns: A publisher that supports `receive(on:)` for thread-confined objects.
    public func threadSafeReference<T: Object>()
        -> Publishers.MakeThreadSafeObjectChangeset<Self, T> where Output == ObjectChange<T> {
            Publishers.MakeThreadSafeObjectChangeset(self)
    }
    /// Enables passing Realm collection changesets to a different dispatch queue.
    ///
    /// Each call to `receive(on:)` on a publisher which emits Realm thread-confined objects must be proceeded by a call to `.threadSafeReference()`
    /// The returned publisher handles the required logic to pass the thread-confined object to the new queue.
    /// Only serial dispatch queues are supported and using other schedulers will result in a fatal error.
    ///
    /// For example, to subscribe on a background thread, do some work there, then pass the collection changeset to the main thread you can do:
    ///
    ///     let cancellable = myCollection.changesetPublisher
    ///         .subscribe(on: DispatchQueue(label: "background queue")
    ///         .print()
    ///         .threadSafeReference()
    ///         .receive(on: DispatchQueue.main)
    ///         .sink { collectionChange in
    ///             // Do things with the collection on the main thread
    ///         }
    ///
    /// - Returns: A publisher that supports `receive(on:)` for thread-confined objects.
    public func threadSafeReference<T: RealmCollection>()
        -> Publishers.MakeThreadSafeCollectionChangeset<Self, T> where Output == RealmCollectionChange<T> {
            Publishers.MakeThreadSafeCollectionChangeset(self)
    }
}

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension RealmCollection where Self: RealmSubscribable { 
    /// A publisher that emits Void each time the collection changes.
    ///
    /// Despite the name, this actually emits *after* the collection has changed.
    public var objectWillChange: Publishers.WillChange<Self> {
        Publishers.WillChange(self)
    }

    /// A publisher that emits the collection each time the collection changes.
    public var publisher: Publishers.Value<Self> {
        Publishers.Value(self)
    }

    /// A publisher that emits a collection changeset each time the collection changes.
    public var changesetPublisher: Publishers.CollectionChangeset<Self> {
        Publishers.CollectionChangeset(self)
    }
}

/// A publisher that emits the object each time the object changes.
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public func valuePublisher<T: Object>(_ object: T) -> Publishers.Value<T> {
    Publishers.Value<T>(object)
}

/// A publisher that emits the collection each time the collection changes.
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public func valuePublisher<T: RealmCollection>(_ collection: T) -> Publishers.Value<T> {
    Publishers.Value<T>(collection)
}

/// A publisher that emits an object changeset each time the object changes.
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public func changesetPublisher<T: Object>(_ object: T) -> Publishers.ObjectChangeset<T> {
    Publishers.ObjectChangeset<T>(object)
}

/// A publisher that emits a collection changeset each time the collection changes.
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public func changesetPublisher<T: RealmCollection>(_ collection: T) -> Publishers.CollectionChangeset<T> {
    Publishers.CollectionChangeset<T>(collection)
}

// MARK: - Object

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension Object: Combine.ObservableObject {
    /// A publisher that emits Void each time the object changes.
    ///
    /// Despite the name, this actually emits *after* the collection has changed.
    public var objectWillChange: Publishers.WillChange<Object> {
        return Publishers.WillChange(self)
    }
}

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension Object: RealmSubscribable {
    /// :nodoc:
    public func _observe<S: Subscriber>(on queue: DispatchQueue?, _ subscriber: S)
        -> NotificationToken where S.Input: Object, S.Failure == Error {
            return observe(on: queue) { (change: ObjectChange<S.Input>) in
                switch change {
                case .change(let object, _):
                    _ = subscriber.receive(object)
                case .deleted:
                    subscriber.receive(completion: .finished)
                case .error(let error):
                    subscriber.receive(completion: .failure(error))
                }
            }
    }

    /// :nodoc:
    public func _observe<S: Subscriber>(_ subscriber: S) -> NotificationToken where S.Input == Void, S.Failure == Never {
        return observe { _ in _ = subscriber.receive() }
    }
}

// MARK: - List

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension List: ObservableObject, RealmSubscribable {
    /// A publisher that emits Void each time the collection changes.
    ///
    /// Despite the name, this actually emits *after* the collection has changed.
    public var objectWillChange: Publishers.WillChange<List> {
        Publishers.WillChange(self)
    }
}

// MARK: - LinkingObjects

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension LinkingObjects: RealmSubscribable {
    /// A publisher that emits Void each time the collection changes.
    ///
    /// Despite the name, this actually emits *after* the collection has changed.
    public var objectWillChange: Publishers.WillChange<LinkingObjects> {
        Publishers.WillChange(self)
    }
}

// MARK: - Results

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension Results: RealmSubscribable {
    /// A publisher that emits Void each time the collection changes.
    ///
    /// Despite the name, this actually emits *after* the collection has changed.
    public var objectWillChange: Publishers.WillChange<Results> {
        Publishers.WillChange(self)
    }
}

// MARK: RealmCollection

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension RealmCollection {
    /// :nodoc:
    public func _observe<S>(on queue: DispatchQueue? = nil, _ subscriber: S)
        -> NotificationToken where S: Subscriber, S.Input == Self, S.Failure == Error {
            // FIXME: we could skip some pointless work in converting the changeset to the Swift type here
            return observe(on: queue) { change in
                switch change {
                case .initial(let collection):
                    _ = subscriber.receive(collection)
                case .update(let collection, deletions: _, insertions: _, modifications: _):
                    _ = subscriber.receive(collection)
                case .error(let error):
                    _ = subscriber.receive(completion: .failure(error))
                }
            }
    }

    /// :nodoc:
    public func _observe<S: Subscriber>(_ subscriber: S) -> NotificationToken where S.Input == Void, S.Failure == Never {
        return observe(on: nil) { _ in _ = subscriber.receive() }
    }
}

@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
extension AnyRealmCollection: RealmSubscribable {
}

// MARK: Subscriptions

/// A subscription which
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public struct ObservationSubscription: Subscription {
    private var token: NotificationToken

    /// :nodoc:
    public var combineIdentifier: CombineIdentifier {
        return CombineIdentifier(token)
    }

    init(token: NotificationToken) {
        self.token = token
    }

    /// :nodoc:
    public func request(_ demand: Subscribers.Demand) {
    }

    /// :nodoc:
    public func cancel() {
        token.invalidate()
    }
}

// MARK: Publishers

/// Combine publishers for Realm types.
///
/// You normally should not create any of these types directly, and should instead use the extension methods which create them.
@available(OSX 10.15, watchOS 6.0, iOS 13.0, iOSApplicationExtension 13.0, OSXApplicationExtension 10.15, *)
public enum Publishers {
    static private func realm<S: Scheduler>(_ config: RLMRealmConfiguration, _ scheduler: S) -> Realm? {
        try? Realm(RLMRealm(configuration: config, queue: scheduler as? DispatchQueue))
    }

    /// A publisher which emits Void each time the object is mutated.
    ///
    /// Despite the name, this actually emits *after* the collection has changed.
    public struct WillChange<Collection: RealmSubscribable>: Publisher where Collection: ThreadConfined {
        /// This publisher cannot fail.
        public typealias Failure = Never
        /// This publisher emits Void.
        public typealias Output = Void
        let object: Collection

        /// :nodoc:
        public init(_ object: Collection) {
            self.object = object
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, Output == S.Input {
            subscriber.receive(subscription: ObservationSubscription(token: self.object._observe(subscriber)))
        }
    }

    /// A publisher which emits an object each time that object is mutated.
    public struct Value<Collection: RealmSubscribable>: Publisher where Collection: ThreadConfined {
        /// This publisher can only fail due to resource exhaustion when creating the worker thread used for change notifications.
        public typealias Failure = Error
        public typealias Output = Collection

        let object: Collection
        let queue: DispatchQueue?
        internal init(_ object: Collection, queue: DispatchQueue? = nil) {
            precondition(object.realm != nil, "Only managed objects can be published")
            self.object = object
            self.queue = queue
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Failure, Output == S.Input {
            subscriber.receive(subscription: ObservationSubscription(token: self.object._observe(on: queue, subscriber)))
        }

        /// Specifies the scheduler on which to perform subscribe, cancel, and request operations.
        ///
        /// For Realm Publishers, this determines which queue the underlying change notifications are sent to. If `receive(on:)` is not used subsequently, it also will determine which queue elements received from the publisher are evaluated on. Currently only serial dispatch queues are supported, and the `options:` parameter is not supported.
        ///
        /// - Parameters:
        ///   - scheduler: The serial dispatch queue to perform the subscription on.
        /// - Returns: A publisher which subscribes on the given scheduler.
        public func subscribe<S: Scheduler>(on scheduler: S) -> Value<Collection> {
            guard let queue = scheduler as? DispatchQueue else {
                fatalError("Cannot subscribe on scheduler \(scheduler): only serial dispatch queues are currently implemented.")
            }
            return Value(object, queue: queue)
        }

        public func receive<S: Scheduler>(on scheduler: S) -> Publishers.Handover<Self, S> {
            return Publishers.Handover(self, scheduler, self.object.realm!)
        }
    }

    /// A publisher which makes receive(on:) work for streams of thread-confined objects
    public struct Handover<Upstream: Publisher, S: Scheduler>: Publisher where Upstream.Output: ThreadConfined {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        private let config: RLMRealmConfiguration
        private let upstream: Upstream
        private let scheduler: S

        internal init(_ upstream: Upstream, _ scheduler: S, _ realm: Realm) {
            self.config = realm.rlmRealm.configuration
            self.upstream = upstream
            self.scheduler = scheduler
        }

        public func receive<Sub>(subscriber: Sub) where Sub: Subscriber, Sub.Failure == Failure, Output == Sub.Input {
            let scheduler = self.scheduler
            let config = self.config
            self.upstream
                .map { ThreadSafeReference(to: $0) }
                .receive(on: scheduler)
                .compactMap { realm(config, scheduler)?.resolve($0) }
                .receive(subscriber: subscriber)
        }
    }

    /// A publisher which makes receive(on:) work for streams of thread-confined objects
    ///
    /// Create using .threadSafeReference()
    public struct MakeThreadSafe<Upstream: Publisher>: Publisher where Upstream.Output: ThreadConfined {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        let upstream: Upstream
        internal init(_ upstream: Upstream) {
            self.upstream = upstream
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Failure, Output == S.Input {
            self.upstream.receive(subscriber: subscriber)
        }

        public func receive<S: Scheduler>(on scheduler: S) -> DeferredHandover<Upstream, S> {
            DeferredHandover(self.upstream, scheduler)
        }
    }

    public struct DeferredHandover<Upstream: Publisher, S: Scheduler>: Publisher where Upstream.Output: ThreadConfined {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        private let upstream: Upstream
        private let scheduler: S

        internal init(_ upstream: Upstream, _ scheduler: S) {
            self.upstream = upstream
            self.scheduler = scheduler
        }

        private enum Handover {
            case object(_ object: Output)
            case tsr(_ tsr: ThreadSafeReference<Output>, config: RLMRealmConfiguration)
        }

        public func receive<Sub>(subscriber: Sub) where Sub: Subscriber, Sub.Failure == Failure, Output == Sub.Input {
            let scheduler = self.scheduler
            self.upstream
                .map { (obj: Output) -> Handover in
                    guard let realm = obj.realm, !realm.isFrozen else { return .object(obj) }
                    return .tsr(ThreadSafeReference(to: obj), config: realm.rlmRealm.configuration)
            }
            .receive(on: scheduler)
            .compactMap { (handover: Handover) -> Output? in
                switch handover {
                case .object(let obj):
                    return obj
                case .tsr(let tsr, let config):
                    return realm(config, scheduler)?.resolve(tsr)
                }
            }
            .receive(subscriber: subscriber)
        }
    }

    /// A publisher which emits ObjectChange<T> each time the observed object is modified
    ///
    /// `receive(on:)` and `subscribe(on:)` can be called directly on this publisher, and calling `.threadSafeReference()` is only required if there is an intermediate transform. If `subscribe(on:)` is used, it should always be the first
    ///
    /// Create this publisher using the `objectChangeset()` function.
    public struct ObjectChangeset<T: Object>: Publisher {
        /// This publisher emits a ObjectChange<T> indicating which object and which properties of that object have changed each time a Realm is refreshed after a write transaction which modifies the observed object.
        public typealias Output = ObjectChange<T>
        /// This publisher reports error via the `.error` case of ObjectChange.
        public typealias Failure = Never

        let object: T
        let queue: DispatchQueue?

        internal init(_ object: T, queue: DispatchQueue? = nil) {
            precondition(object.realm != nil, "Only managed objects can be published")
            precondition(!object.isInvalidated, "Object is invalidated or deleted")
            self.object = object
            self.queue = queue
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, Output == S.Input {
            let token = self.object.observe(on: self.queue) { change in
                switch change {
                case .change(let o, let properties):
                    _ = subscriber.receive(.change(o as! T, properties))
                case .error(let error):
                    _ = subscriber.receive(.error(error))
                case .deleted:
                    subscriber.receive(completion: .finished)
                }
            }
            subscriber.receive(subscription: ObservationSubscription(token: token))
        }

        /// Specifies the scheduler on which to perform subscribe, cancel, and request operations.
        ///
        /// For Realm Publishers, this determines which queue the underlying change notifications are sent to. If `receive(on:)` is not used subsequently, it also will determine which queue elements received from the publisher are evaluated on. Currently only serial dispatch queues are supported, and the `options:` parameter is not supported.
        ///
        /// - Parameters:
        ///   - scheduler: The serial dispatch queue to perform the subscription on.
        /// - Returns: A publisher which subscribes on the given scheduler.
        public func subscribe<S: Scheduler>(on scheduler: S) -> ObjectChangeset<T> {
            guard let queue = scheduler as? DispatchQueue else {
                fatalError("Cannot subscribe on scheduler \(scheduler): only serial dispatch queues are currently implemented.")
            }
            return ObjectChangeset(object, queue: queue)
        }

        /// Specifies the scheduler on which to receive elements from the publisher.
        ///
        /// You most likely want to use `subscribe(on:)` rather than this function.
        ///
        /// You use the `receive(on:)` operator to receive results on a specific scheduler, such as performing UI work on the main run loop.
        /// In contrast with `subscribe(on:)`, which affects upstream messages, `receive(on:)` changes the execution context of downstream messages.
        /// In the following example, requests to `jsonPublisher` are performed on `backgroundQueue`, but elements received from it are performed on `RunLoop.main`.
        ///
        ///     let jsonPublisher = MyJSONLoaderPublisher() // Some publisher.
        ///     let labelUpdater = MyLabelUpdateSubscriber() // Some subscriber that updates the UI.
        ///
        ///     jsonPublisher
        ///         .subscribe(on: backgroundQueue)
        ///         .receiveOn(on: RunLoop.main)
        ///         .subscribe(labelUpdater)
        ///
        /// - Parameters:
        ///   - scheduler: The scheduler the publisher is to use for element delivery.
        ///   - options: Scheduler options that customize the element delivery.
        /// - Returns: A publisher that delivers elements using the specified scheduler.
        public func receive<S: Scheduler>(on scheduler: S) -> DeferredHandoverObjectChangeset<Self, T, S> {
            DeferredHandoverObjectChangeset(self, scheduler)
        }
    }

    public struct MakeThreadSafeObjectChangeset<Upstream: Publisher, T: Object>: Publisher where Upstream.Output == ObjectChange<T> {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        let upstream: Upstream
        internal init(_ upstream: Upstream) {
            self.upstream = upstream
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Failure, Output == S.Input {
            self.upstream.receive(subscriber: subscriber)
        }

        public func receive<S: Scheduler>(on scheduler: S) -> DeferredHandoverObjectChangeset<Upstream, T, S> {
            DeferredHandoverObjectChangeset(self.upstream, scheduler)
        }
    }

    public struct DeferredHandoverObjectChangeset<Upstream: Publisher, T: Object, S: Scheduler>: Publisher where Upstream.Output == ObjectChange<T> {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        private let upstream: Upstream
        private let scheduler: S

        internal init(_ upstream: Upstream, _ scheduler: S) {
            self.upstream = upstream
            self.scheduler = scheduler
        }

        private enum Handover {
            case passthrough(_ change: ObjectChange<T>)
            case tsr(_ tsr: ThreadSafeReference<T>, _ properties: [PropertyChange], config: RLMRealmConfiguration)
        }

        public func receive<Sub>(subscriber: Sub) where Sub: Subscriber, Sub.Failure == Failure, Output == Sub.Input {
            let scheduler = self.scheduler
            self.upstream
                .map { (change: Output) -> Handover in
                    guard case .change(let obj, let properties) = change else { return .passthrough(change) }
                    guard let realm = obj.realm, !realm.isFrozen else { return .passthrough(change) }
                    return .tsr(ThreadSafeReference(to: obj), properties, config: realm.rlmRealm.configuration)
                }
                .receive(on: scheduler)
                .compactMap { (handover: Handover) -> Output? in
                    switch handover {
                    case .passthrough(let change):
                        return change
                    case .tsr(let tsr, let properties, let config):
                        if let resolved = realm(config, scheduler)?.resolve(tsr) {
                            return .change(resolved, properties)
                        }
                        return nil
                    }
                }
                .receive(subscriber: subscriber)
        }
    }

    public struct CollectionChangeset<Collection: RealmCollection>: Publisher {
        public typealias Output = RealmCollectionChange<Collection>
        /// This publisher reports error via the `.error` case of RealmCollectionChange..
        public typealias Failure = Never

        let collection: Collection
        let queue: DispatchQueue?
        internal init(_ collection: Collection, queue: DispatchQueue? = nil) {
            precondition(collection.realm != nil, "Only managed collections can be published")
            self.collection = collection
            self.queue = queue
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, Output == S.Input {
            let token = self.collection.observe(on: self.queue) { change in
                _ = subscriber.receive(change)
            }
            subscriber.receive(subscription: ObservationSubscription(token: token))
        }

        /// Specifies the scheduler on which to perform subscribe, cancel, and request operations.
        ///
        /// For Realm Publishers, this determines which queue the underlying change notifications are sent to. If `receive(on:)` is not used subsequently, it also will determine which queue elements received from the publisher are evaluated on. Currently only serial dispatch queues are supported, and the `options:` parameter is not supported.
        ///
        /// - Parameters:
        ///   - scheduler: The serial dispatch queue to perform the subscription on.
        /// - Returns: A publisher which subscribes on the given scheduler.
        public func subscribe<S: Scheduler>(on scheduler: S) -> CollectionChangeset<Collection> {
            guard let queue = scheduler as? DispatchQueue else {
                fatalError("Cannot subscribe on scheduler \(scheduler): only serial dispatch queues are currently implemented.")
            }
            return CollectionChangeset(collection, queue: queue)
        }

        public func receive<S: Scheduler>(on scheduler: S) -> DeferredHandoverCollectionChangeset<Self, Collection, S> {
            DeferredHandoverCollectionChangeset(self, scheduler)
        }
    }

    public struct MakeThreadSafeCollectionChangeset<Upstream: Publisher, T: RealmCollection>: Publisher where Upstream.Output == RealmCollectionChange<T> {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        let upstream: Upstream
        internal init(_ upstream: Upstream) {
            self.upstream = upstream
        }

        /// :nodoc:
        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Failure, Output == S.Input {
            self.upstream.receive(subscriber: subscriber)
        }

        public func receive<S: Scheduler>(on scheduler: S) -> DeferredHandoverCollectionChangeset<Upstream, T, S> {
            DeferredHandoverCollectionChangeset(self.upstream, scheduler)
        }
    }

    public struct DeferredHandoverCollectionChangeset<Upstream: Publisher, T: RealmCollection, S: Scheduler>: Publisher where Upstream.Output == RealmCollectionChange<T> {
        /// :nodoc:
        public typealias Failure = Upstream.Failure
        /// :nodoc:
        public typealias Output = Upstream.Output

        private let upstream: Upstream
        private let scheduler: S

        internal init(_ upstream: Upstream, _ scheduler: S) {
            self.upstream = upstream
            self.scheduler = scheduler
        }

        private enum Handover {
            case passthrough(_ change: RealmCollectionChange<T>)
            case initial(_ tsr: ThreadSafeReference<T>, config: RLMRealmConfiguration)
            case update(_ tsr: ThreadSafeReference<T>, deletions: [Int], insertions: [Int], modifications: [Int], config: RLMRealmConfiguration)
        }

        public func receive<Sub>(subscriber: Sub) where Sub: Subscriber, Sub.Failure == Failure, Output == Sub.Input {
            let scheduler = self.scheduler
            self.upstream
                .map { (change: Output) -> Handover in
                    switch change {
                    case .initial(let collection):
                        guard let realm = collection.realm, !realm.isFrozen else { return .passthrough(change) }
                        return .initial(ThreadSafeReference(to: collection), config: realm.rlmRealm.configuration)
                    case .update(let collection, deletions: let deletions, insertions: let insertions, modifications: let modifications):
                        guard let realm = collection.realm, !realm.isFrozen else { return .passthrough(change) }
                        return .update(ThreadSafeReference(to: collection), deletions: deletions, insertions: insertions, modifications: modifications, config: realm.rlmRealm.configuration)
                    case .error:
                        return .passthrough(change)
                    }
                }
                .receive(on: scheduler)
                .compactMap { (handover: Handover) -> Output? in
                    switch handover {
                    case .passthrough(let change):
                        return change
                    case .initial(let tsr, config: let config):
                        if let resolved = realm(config, scheduler)?.resolve(tsr) {
                            return .initial(resolved)
                        }
                        return nil
                    case .update(let tsr, deletions: let deletions, insertions: let insertions, modifications: let modifications, config: let config):
                        if let resolved = realm(config, scheduler)?.resolve(tsr) {
                            return .update(resolved, deletions: deletions, insertions: insertions, modifications: modifications)
                        }
                        return nil
                    }
                }
                .receive(subscriber: subscriber)
        }
    }
}

#endif // canImport(Combine)
