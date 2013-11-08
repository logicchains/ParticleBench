#lang racket
(require sdl/sdl/main) ;https://github.com/cosmez/racket-sdl
(require RacketGL/opengl/main) ;https://github.com/stephanh42/RacketGL
(require ffi/vector)
(require racket/flonum)
(require racket/unsafe/ops)

(define *SCREEN_WIDTH* 800)
(define *SCREEN_HEIGHT* 600)
(define *TITLE* "ParticleBench")

(define *MIN_X* -80.0)
(define *MAX_X* 80.0)
(define *MIN_Y* -90.0)
(define *MAX_Y* 50.0)
(define *MIN_DEPTH* 50.0)
(define *MAX_DEPTH* 250.0)

(define *START_RANGE* 15.0)
(define *START_X* (+ *MIN_X* (/ (+ *MIN_X* *MAX_X*) 2) ) )
(define *START_Y* *MAX_Y*)
(define *START_DEPTH* (+ *MIN_DEPTH* (/ (+ *MIN_DEPTH* *MAX_DEPTH*) 2) ))

(define *POINTS_PER_SEC* 2000)
(define *MAX_INIT_VEL* 7.0)
(define *MAX_LIFE* 5) ;seconds
(define *MAX_SCALE* 4.0)

(define *WIND_CHANGE* 2.0)
(define *MAX_WIND* 3.0)
(define *SPAWN_INTERVAL* 0.01 )
(define *RUNNING_TIME* (* *MAX_LIFE* 5))
(define *MAX_PTS* (* *RUNNING_TIME* *POINTS_PER_SEC*))

(define init-t 0.0)
(define end-t 0.0)
(define frame-dur 0.0)
(define spwn-tmr 0.0)
(define cleanup-tmr 0.0)
(define run-tmr 0.0)
(define frames (make-vector (* *RUNNING_TIME* 1000) 0.0)  )
(define cur-frame 0)

(define windX 0.0) 
(define windY 0.0)
(define windZ 0.0)
(define grav 0.5)

(define sdl-window #f)
(define sdl-renderer #f)
(define gl-context #f)
(define screen-surface #f)

(define vbo #f)
(define cur-vertex 0)
(define ambient (f32vector 0.8 0.05 0.1 1.0))
(define diffuse (f32vector 1.0 1.0 1.0 1.0))
(define light-pos (f32vector (+ *MIN_X* (/ (- *MAX_X* *MIN_X*) 2) ) *MAX_Y* *MIN_DEPTH* 0.0))

(struct pt (x y z vx vy vz R life is)
  #:mutable) 

(define max-pt 0)      
(define min-pt 0)  
(define seed 1234569)

(define pts (make-vector *MAX_PTS* [pt 0 0 0 0 0 0 0 0 0])) 


(define vertex-normal-array
  (f32vector
   -1.0 -1.0 1.0 0.0 0.0 1.0
   1.0 -1.0 1.0 0.0 0.0 1.0
   1.0 1.0 1.0 0.0 0.0 1.0
   -1.0 1.0 1.0 0.0 0.0 1.0
   -1.0 -1.0 -1.0 0.0 0.0 -1.0
   -1.0 1.0 -1.0 0.0 0.0 -1.0
   1.0 1.0 -1.0 0.0 0.0 -1.0
   1.0 -1.0 -1.0 0.0 0.0 -1.0
   -1.0 1.0 -1.0 0.0 1.0 0.0
   -1.0 1.0 1.0 0.0 1.0 0.0
   1.0 1.0 1.0 0.0 1.0 0.0
   1.0 1.0 -1.0 0.0 1.0 0.0
   -1.0 -1.0 -1.0 0.0 -1.0 0.0
   1.0 -1.0 -1.0 0.0 -1.0 0.0
   1.0 -1.0 1.0 0.0 -1.0 0.0
   -1.0 -1.0 1.0 0.0 -1.0 0.0
   1.0 -1.0 -1.0 1.0 0.0 0.0
   1.0 1.0 -1.0 1.0 0.0 0.0
   1.0 1.0 1.0 1.0 0.0 0.0
   1.0 -1.0 1.0 1.0 0.0 0.0
   -1.0 -1.0 -1.0 -1.0 0.0 0.0
   -1.0 -1.0 1.0 -1.0 0.0 0.0
   -1.0 1.0 1.0 -1.0 0.0 0.0
   -1.0 1.0 -1.0 -1.0 0.0 0.0)
  )

(define (new-pt)
  (unsafe-vector-set! pts max-pt ( pt
                            (unsafe-fl- (unsafe-fl+ 0.0 (unsafe-fl* (random) *START_RANGE*)) (unsafe-fl/ *START_RANGE* 2.0) )
                            *START_Y*
                            (unsafe-fl- (unsafe-fl+ *START_DEPTH* (unsafe-fl* (random) *START_RANGE*)) (unsafe-fl/ *START_RANGE* 2.0) )
                            (unsafe-fl* (random) *MAX_INIT_VEL*)
                            (unsafe-fl* (random) *MAX_INIT_VEL*)
                            (unsafe-fl* (random) *MAX_INIT_VEL*)
                            (/ (unsafe-fl* (random) *MAX_SCALE* ) 2.0)
                            (* (random) *MAX_LIFE*)
                            1
                            )
               )
  (set! max-pt (+ max-pt 1) )
  )

(define (spwn-pts secs)
  (let ([num (* secs *POINTS_PER_SEC*)])
    (for ([i (in-range 0 num )]) (new-pt) )
    )  
  )

(define (move-pts secs)
  (for ([i (in-range min-pt max-pt)]
        #:when (equal? (unsafe-struct*-ref (unsafe-vector*-ref pts i) 8) 1) )
    (let ([apt (unsafe-vector*-ref pts i)]) (begin
                                      ( unsafe-struct*-set! apt 0 (unsafe-fl+ (unsafe-struct*-ref apt 0) (unsafe-fl* (unsafe-struct*-ref apt 3) secs) ) )
                                      ( unsafe-struct*-set! apt 1 (unsafe-fl+ (unsafe-struct*-ref apt 1) (unsafe-fl* (unsafe-struct*-ref apt 4) secs) ) )  
                                      ( unsafe-struct*-set! apt 2 (unsafe-fl+ (unsafe-struct*-ref apt 2) (unsafe-fl* (unsafe-struct*-ref apt 5) secs) ) )
                                      ( unsafe-struct*-set! apt 3 (unsafe-fl+ (unsafe-struct*-ref apt 3) (unsafe-fl* (unsafe-fl/ 1.0 (unsafe-struct*-ref apt 6)) windX)))
                                      ( unsafe-struct*-set! apt 4 (unsafe-fl+ (unsafe-struct*-ref apt 4) (unsafe-fl* (unsafe-fl/ 1.0 (unsafe-struct*-ref apt 6)) windY)))
                                      ( unsafe-struct*-set! apt 5 (unsafe-fl+ (unsafe-struct*-ref apt 5) (unsafe-fl* (unsafe-fl/ 1.0 (unsafe-struct*-ref apt 6)) windZ)))
                                      ( unsafe-struct*-set! apt 4 (unsafe-fl- (unsafe-struct*-ref apt 4) grav) )
                                      ( unsafe-struct*-set! apt 7 (unsafe-fl- (unsafe-struct*-ref apt 7) secs) )
                                      ( if (unsafe-fl> 0.0 (unsafe-struct*-ref apt 7) ) (unsafe-struct*-set! apt 8 0) #f )
                                      )
      )
    )
  )
(define (check-colls)
  (for ([i (in-range min-pt max-pt)]
        #:when (equal? (unsafe-struct*-ref (unsafe-vector*-ref pts i) 8) 1) ) (begin        
                                                         (if (unsafe-fl< (unsafe-struct*-ref (unsafe-vector*-ref pts i) 0) *MIN_X*) (begin 
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 0 (unsafe-fl+ *MIN_X* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 6)) )
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 3 (unsafe-fl* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 0) -1.1)) ) #f)
                                                         (if (unsafe-fl> (unsafe-struct*-ref (unsafe-vector*-ref pts i) 0) *MAX_X*) (begin 
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 0 (unsafe-fl- *MAX_X* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 6)) )
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 3 (unsafe-fl* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 0) -1.1)) ) #f)
                                                         (if (unsafe-fl< (unsafe-struct*-ref (unsafe-vector*-ref pts i) 1) *MIN_Y*) (begin 
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 1 (unsafe-fl+ *MIN_Y* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 6)) )
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 4 (unsafe-fl* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 1) -1.1)) ) #f)
                                                         (if (unsafe-fl> (unsafe-struct*-ref (unsafe-vector*-ref pts i) 1) *MAX_Y*) (begin 
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 1 (unsafe-fl- *MAX_Y* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 6)) )
                                                                                                     (unsafe-struct*-set! (unsafe-vector*-ref pts i) 4 (unsafe-fl* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 1) -1.1)) ) #f)
                                                         (if (unsafe-fl< (unsafe-struct*-ref (unsafe-vector*-ref pts i) 2) *MIN_DEPTH*) (begin 
                                                                                                         (unsafe-struct*-set! (unsafe-vector*-ref pts i) 2 (+ *MIN_DEPTH* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 6)) )
                                                                                                         (unsafe-struct*-set! (unsafe-vector*-ref pts i) 5 (* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 2) -1.1)) ) #f)
                                                         (if (unsafe-fl> (unsafe-struct*-ref (unsafe-vector*-ref pts i) 2) *MAX_DEPTH*) (begin 
                                                                                                         (unsafe-struct*-set! (unsafe-vector*-ref pts i) 2 (unsafe-fl- *MAX_DEPTH* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 6)) )
                                                                                                         (unsafe-struct*-set! (unsafe-vector*-ref pts i) 5 (unsafe-fl* (unsafe-struct*-ref (unsafe-vector*-ref pts i) 2) -1.1)) ) #f)
                                                         )
    )
  )

(define (do-wind)
  (set! windX (unsafe-fl+ (unsafe-fl* (unsafe-fl- (unsafe-fl* (random) *WIND_CHANGE*) (unsafe-fl/ *WIND_CHANGE* 2.0) ) frame-dur) windX) )
  (set! windY (unsafe-fl+ (unsafe-fl* (unsafe-fl- (unsafe-fl* (random) *WIND_CHANGE*) (unsafe-fl/ *WIND_CHANGE* 2.0) ) frame-dur) windY) )
  (set! windZ (unsafe-fl+ (unsafe-fl* (unsafe-fl- (unsafe-fl* (random) *WIND_CHANGE*) (unsafe-fl/ *WIND_CHANGE* 2.0) ) frame-dur) windZ) )
  (if (unsafe-fl> (flabs windX) *MAX_WIND*) (set! windX (* windX -0.5) ) #f)
  (if (unsafe-fl> (flabs windY) *MAX_WIND*) (set! windY (* windY -0.5) ) #f)
  (if (unsafe-fl> (flabs windZ) *MAX_WIND*) (set! windZ (* windZ -0.5) ) #f)
  )

(define (render-pts)
  (for ([i (in-range min-pt max-pt)]
        #:when (equal? (unsafe-struct*-ref (unsafe-vector*-ref pts i) 8) 1) )
    (let ([apt (unsafe-vector*-ref pts i)]) (begin 
                                      (glPopMatrix)
                                      (glPushMatrix) 
                                      (glTranslatef (unsafe-struct*-ref apt 0) (unsafe-struct*-ref apt 1) (- 0 (unsafe-struct*-ref apt 2)) ) 
                                      (glScalef (unsafe-fl* (unsafe-struct*-ref apt 6) 2.0) (unsafe-fl* (unsafe-struct*-ref apt 6) 2.0) (unsafe-fl* (unsafe-struct*-ref apt 6) 2.0))
                                      (glDrawArrays GL_QUADS 0 24)        
                                      ) 
      )
    )
  (SDL_RenderPresent sdl-renderer)
  )

(define (cleanup-pt-pool)
  (for ([i (in-range min-pt max-pt)]
        #:final (equal? (pt-is (unsafe-vector*-ref pts i)) 1) )
    (if (equal? (pt-is (unsafe-vector*-ref pts i)) 1) (set! min-pt i) #f)
    )
  )

(define (load-cube-to-gpu)
  (set! vbo (u32vector-ref (glGenBuffers 1) 0))
  (glBindBuffer GL_ARRAY_BUFFER vbo)
  (glBufferData GL_ARRAY_BUFFER
                (gl-vector-sizeof vertex-normal-array)
                vertex-normal-array
                GL_STATIC_DRAW)  
  (glEnableClientState GL_VERTEX_ARRAY)
  (glEnableClientState GL_NORMAL_ARRAY)
  (glVertexPointer 3 GL_FLOAT 24 0)
  (glNormalPointer GL_FLOAT 12 0)
  (glMatrixMode GL_MODELVIEW)
  )

(define (init) 
  (random-seed seed)
  (SDL_Init SDL_INIT_VIDEO)
  (set! sdl-window (SDL_CreateWindow *TITLE* SDL_WINDOWPOS_UNDEFINED SDL_WINDOWPOS_UNDEFINED *SCREEN_WIDTH* *SCREEN_HEIGHT* #x00000002))
  (set! sdl-renderer (SDL_CreateRenderer sdl-window -1 0))
  (if sdl-window
      (set! screen-surface (SDL_GetWindowSurface sdl-window))
      (printf "Window could not be created! SDL_Error: ~a\n" (SDL_GetError)))
  #t)

(define (init-gl)
  (set! gl-context (SDL_GL_CreateContext sdl-window))
  (SDL_GL_MakeCurrent sdl-window gl-context)  
  (glEnable GL_DEPTH_TEST)
  (glEnable GL_LIGHTING)
  (glClearColor 0.1 0.1 0.6 1.0)
  (glClearDepth 1)
  (glDepthFunc GL_LEQUAL)
  
  (glLightfv GL_LIGHT0 GL_AMBIENT ambient)
  (glLightfv GL_LIGHT0 GL_DIFFUSE diffuse)
  (glLightfv GL_LIGHT0 GL_POSITION light-pos)
  (glEnable GL_LIGHT0)
  
  (glViewport 0 0 *SCREEN_WIDTH* *SCREEN_HEIGHT*)
  (glMatrixMode GL_PROJECTION)
  (glLoadIdentity)
  (glFrustum -1 1 -1 1 1.0 1000.0)
  (glRotatef 20.0 1.0 0.0 0.0)
  (glMatrixMode GL_MODELVIEW)
  (glLoadIdentity)
  (glPushMatrix)
  )

(define (close) 
  (glDisableClientState GL_VERTEX_ARRAY)
  (glDisableClientState GL_NORMAL_ARRAY)
  (SDL_GL_DeleteContext gl-context)
  (SDL_DestroyWindow sdl-window)
  (SDL_Quit))

(define (main-loop)
  (set! init-t (/ (current-inexact-milliseconds) 1000.0) )
  (move-pts frame-dur)
  (do-wind)
  (if (>= spwn-tmr *SPAWN_INTERVAL*) (begin (spwn-pts *SPAWN_INTERVAL*) (set! spwn-tmr (- spwn-tmr *SPAWN_INTERVAL*)) ) #f)
  (if (>= cleanup-tmr (/ *MAX_LIFE* 1000) ) (begin (cleanup-pt-pool) (set! cleanup-tmr 0) ) #f)
  (check-colls)
  (glClear GL_COLOR_BUFFER_BIT)
  (glClear GL_DEPTH_BUFFER_BIT)
  (render-pts)
  (SDL_GL_SwapWindow sdl-window)
  (set! end-t (/ (current-inexact-milliseconds) 1000.0) )
  (set! frame-dur (- end-t init-t) )
  (set! spwn-tmr (+ spwn-tmr frame-dur) )
  (set! cleanup-tmr (+ cleanup-tmr frame-dur) )
  (set! run-tmr (+ run-tmr frame-dur) )
  (if (>= run-tmr (/ *MAX_LIFE* 1000) ) (begin ( vector-set! frames cur-frame frame-dur) ( set! cur-frame (+ cur-frame 1) ) ) #f )
  (if (< run-tmr *RUNNING_TIME*) (main-loop)
      (let ([sum 0]) (begin 
                       (for ([i (in-range 0 cur-frame)]) (set! sum (+ sum (unsafe-vector*-ref frames i) ) ) )
                       (display "Average framerate was: ") (display (/ 1 (/ sum cur-frame) ) ) (display " frames per second.\n") )
        )
      )
  )

(init)
(init-gl)
(load-cube-to-gpu)
(main-loop)
(close)
