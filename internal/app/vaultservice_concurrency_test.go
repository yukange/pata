package app

import (
	"fmt"
	"sync"
	"testing"

	"pata/internal/storage/markdown"
)

func TestVaultServiceConcurrentMutationsPreserveActivities(t *testing.T) {
	for _, owner := range []string{"task", "day_plan"} {
		t.Run(owner, func(t *testing.T) {
			s := &VaultService{}
			v, err := s.openVault(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			defer s.stopWatcher()
			task, err := s.CreateTask(CreateTaskInput{Title: "并发写入"})
			if err != nil {
				t.Fatal(err)
			}
			const date = "2026-10-26"
			const count = 16
			start := make(chan struct{})
			errs := make(chan error, count*2+1)
			stopScan := make(chan struct{})
			scanDone := make(chan struct{})
			go func() {
				defer close(scanDone)
				<-start
				for {
					select {
					case <-stopScan:
						return
					default:
						if err := s.RescanVault(); err != nil {
							errs <- err
							return
						}
					}
				}
			}()
			var wg sync.WaitGroup
			for i := 0; i < count; i++ {
				wg.Add(2)
				go func(i int) {
					defer wg.Done()
					<-start
					input := CreateActivityInput{Body: fmt.Sprintf("record %d", i)}
					if owner == "task" {
						input.TaskID = task.ID
					} else {
						input.Date = date
					}
					_, err := s.createActivity(input, markdown.SourceAgent)
					errs <- err
				}(i)
				go func() {
					defer wg.Done()
					<-start
					var err error
					if owner == "task" {
						_, err = s.UpdateTask(UpdateTaskInput{ID: task.ID, Title: "GUI 修改", Status: markdown.TaskStatusTodo})
					} else {
						_, err = s.SaveDayPlan(date, []string{task.ID})
					}
					errs <- err
				}()
			}
			close(start)
			wg.Wait()
			close(stopScan)
			<-scanDone
			close(errs)
			for err := range errs {
				if err != nil {
					t.Fatal(err)
				}
			}
			reopened, err := markdown.NewVault(v.RootPath)
			if err != nil {
				t.Fatal(err)
			}
			var activities []markdown.Activity
			if owner == "task" {
				stored, _ := reopened.Index.GetTask(task.ID)
				activities = stored.Activities
				if stored.Title != "GUI 修改" {
					t.Fatalf("task properties lost: %+v", stored)
				}
			} else {
				stored, _ := reopened.Index.GetDayPlan(date)
				activities = stored.Activities
				if len(stored.TaskIDs) != 1 || stored.TaskIDs[0] != task.ID {
					t.Fatalf("plan task IDs lost: %+v", stored)
				}
			}
			bodies := make(map[string]bool)
			for _, activity := range activities {
				bodies[activity.Body] = true
				if activity.By != markdown.SourceAgent {
					t.Fatalf("activity source lost: %+v", activity)
				}
			}
			if len(activities) != count || len(bodies) != count {
				t.Fatalf("%d appends succeeded, recovered %d activities and %d distinct bodies", count, len(activities), len(bodies))
			}
		})
	}
}
