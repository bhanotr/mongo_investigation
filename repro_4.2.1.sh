#!/bin/bash


db=/home/ritwik/data_421
MONGO_BIN=/home/ritwik/mongo-test/mongo

MONGO_PORT=27017

FLAMEGRAPH_DIR=/home/ritwik/FlameGraph 
PERF_DATA_FILE="perf.data.421"
SVG_FILE="flamegraph.421.svg"


function start {
    echo "Starting test setup for ${MONGO_BIN} on port ${MONGO_PORT}..."
    
    rm -rf $db
    mkdir -p $db
    
    killall -9 -w mongod mongo
    
    ${MONGO_BIN}/mongod --dbpath $db --port ${MONGO_PORT} --logpath $db.log --wiredTigerCacheSizeGB 2 --fork
    sleep 3
}

function start_perf {
    echo "Starting perf recording..."
    PID=$(pgrep mongod | head -n 1) 
    
    if [ -z "$PID" ]; then
        echo "Error: mongod PID not found. Exiting."
        exit 1
    fi
    
    sudo perf record -F 99 -g -p $PID -o $PERF_DATA_FILE &
    PERF_PID=$!
    sleep 1
    echo "Perf recording started on PID $PID (Perf PID: $PERF_PID)"
}

function stop_perf {
    echo "Stopping perf recording..."
    sudo killall perf 
    sleep 2
}

function process_perf_data {
    echo "Processing perf data into Flame Graph..."
    
    sudo perf script -i $PERF_DATA_FILE | ${FLAMEGRAPH_DIR}/stackcollapse-perf.pl > out.folded
    
    ${FLAMEGRAPH_DIR}/flamegraph.pl out.folded > $SVG_FILE
    echo "Flame Graph generated: $SVG_FILE"
}

function insert {
    ${MONGO_BIN}/mongo --port ${MONGO_PORT} --eval '
        
        // adjust this
        load("/home/ritwik/mongo-debug/mongo/jstests/libs/parallelTester.js")

        for (var b = 0; b < 10; b++) {
            spec = {x: 1, a: 1, _id: 1}
            spec["b"+b] = 1
            db.c0.createIndex(spec, {unique: false})
            db.c1.createIndex(spec, {unique: false})
            db.c2.createIndex(spec, {unique: false})
            db.c3.createIndex(spec, {unique: false})
            db.c4.createIndex(spec, {unique: false})
        }
    
        nthreads = 2
        threads = []
    
        for (var t = 0; t < nthreads; t++) {
    
            thread = new ScopedThread(function(t) {
    
                size = 20
                count = 500*1000; // REDUCED LOAD
                every = 1000
                x = "x".repeat(size)
    
                c = db["c"+t]
    
                for (var i=0; i<count; i++) {
                    if (i % every == 0) {
                        if (i > 0)
                            c.insertMany(many)
                        many = []
                    }
                    doc = {_id:i, x:x, b0:0, b1:0, b2:0, b3:0, b4:0, b5:0, b6:0, b7:0, b8:0, b9:0, a: 0}
                    many.push(doc)
                    if (i%10000==0) print(t, i)
                }
    
            }, t)
            threads.push(thread)
            thread.start()
        }
        for (var t = 0; t < nthreads; t++)
            threads[t].join()
    '
}

function update {
    ${MONGO_BIN}/mongo --port ${MONGO_PORT} --eval '

        // adjust this
        load("/home/ritwik/mongo-debug/mongo/jstests/libs/parallelTester.js")
    
        nthreads = 2
        threads = []
    
        for (var t = 0; t < nthreads; t++) {
            thread = new ScopedThread(function(t) {
                mod = 100
                c = db["c"+t]
                for (var i = 0; i < 20; i++)
                    c.updateMany({_id: {$mod: [mod, i%mod]}}, {$inc: {a: 1}})
                
            }, t)
            threads.push(thread)
            thread.start()
        }
        for (var t = 0; t < nthreads; t++)
            threads[t].join()

    '
}



start
start_perf  
insert      
update      
stop_perf   

process_perf_data
