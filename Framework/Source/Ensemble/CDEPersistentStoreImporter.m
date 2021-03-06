//
//  CDEPersistentStoreImporter.m
//  Ensembles
//
//  Created by Drew McCormack on 21/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEPersistentStoreImporter.h"
#import "CDEStoreModificationEvent.h"
#import "CDEEventStore.h"
#import "CDEEventBuilder.h"
#import "CDEEventRevision.h"

@implementation CDEPersistentStoreImporter

@synthesize persistentStorePath = persistentStorePath;
@synthesize eventStore = eventStore;
@synthesize managedObjectModel = managedObjectModel;

- (id)initWithPersistentStoreAtPath:(NSString *)newPath managedObjectModel:(NSManagedObjectModel *)newModel eventStore:(CDEEventStore *)newEventStore;
{
    self = [super init];
    if (self) {
        persistentStorePath = [newPath copy];
        eventStore = newEventStore;
        managedObjectModel = newModel;
    }
    return self;
}

- (void)importWithCompletion:(CDECompletionBlock)completion
{
    __block NSError *error = nil;
    
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    context.persistentStoreCoordinator = coordinator;
    
    NSURL *storeURL = [NSURL fileURLWithPath:persistentStorePath];
    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error];
    
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
        return;
    }
    
    NSManagedObjectContext *eventContext = eventStore.managedObjectContext;
    CDEEventBuilder *eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:self.eventStore];
    eventBuilder.ensemble = self.ensemble;
    [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeSave];
    [eventBuilder performBlockAndWait:^{
        eventBuilder.event.globalCount = 0;
    }];
    
    NSMutableSet *allObjects = [[NSMutableSet alloc] initWithCapacity:1000];
    [context performBlockAndWait:^{
        for (NSEntityDescription *entity in managedObjectModel.entities) {
            NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:entity.name];
            fetch.fetchBatchSize = 100;
            fetch.includesSubentities = NO;
            
            NSArray *objects = [context executeFetchRequest:fetch error:&error];
            if (!objects) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(error);
                });
                return;
            }
            [allObjects addObjectsFromArray:objects];
        }
        
        [eventBuilder addChangesForInsertedObjects:allObjects inManagedObjectContext:context];
    }];
        
    [eventContext performBlockAndWait:^{
        [eventContext save:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }];
}

@end
