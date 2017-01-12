use f77_zmq
use omp_lib

integer, pointer :: thread_id 
integer(omp_lock_kind) :: zmq_lock


BEGIN_PROVIDER [ integer(ZMQ_PTR), zmq_context ]
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Context for the ZeroMQ library
  END_DOC
  call omp_init_lock(zmq_lock)
  zmq_context = 0_ZMQ_PTR
END_PROVIDER


 BEGIN_PROVIDER [ character*(128), qp_run_address ]
&BEGIN_PROVIDER [ integer, zmq_port_start ]
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Address of the qp_run socket
  ! Example : tcp://130.120.229.139:12345
  END_DOC
  character*(128)                :: buffer
  call getenv('QP_RUN_ADDRESS',buffer)
  if (trim(buffer) == '') then
    print *,  'This run should be started with the qp_run command'
    stop -1
  endif
  
  integer                        :: i
  do i=len(buffer),1,-1
    if ( buffer(i:i) == ':') then
      qp_run_address = trim(buffer(1:i-1))
      read(buffer(i+1:), *) zmq_port_start
      exit
    endif
  enddo
END_PROVIDER

 BEGIN_PROVIDER [ character*(128), zmq_socket_pull_tcp_address    ]
&BEGIN_PROVIDER [ character*(128), zmq_socket_pair_inproc_address ]
&BEGIN_PROVIDER [ character*(128), zmq_socket_push_tcp_address    ]
&BEGIN_PROVIDER [ character*(128), zmq_socket_pull_inproc_address ]
&BEGIN_PROVIDER [ character*(128), zmq_socket_push_inproc_address ]
&BEGIN_PROVIDER [ character*(128), zmq_socket_sub_tcp_address ]
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket which pulls the results (2)
  END_DOC
  character*(8), external        :: zmq_port

  zmq_socket_sub_tcp_address     = trim(qp_run_address)//':'//zmq_port(1)//' '
  zmq_socket_pull_tcp_address    = 'tcp://*:'//zmq_port(2)//' '
  zmq_socket_push_tcp_address    = trim(qp_run_address)//':'//zmq_port(2)//' '
  zmq_socket_pull_inproc_address = 'inproc://'//zmq_port(2)//' '
  zmq_socket_push_inproc_address = zmq_socket_pull_inproc_address
  zmq_socket_pair_inproc_address = 'inproc://'//zmq_port(3)//' '

  ! /!\ Don't forget to change subroutine reset_zmq_addresses
END_PROVIDER

subroutine reset_zmq_addresses
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket which pulls the results (2)
  END_DOC
  character*(8), external        :: zmq_port

  zmq_socket_sub_tcp_address     = trim(qp_run_address)//':'//zmq_port(1)//' '
  zmq_socket_pull_tcp_address    = 'tcp://*:'//zmq_port(2)//' '
  zmq_socket_push_tcp_address    = trim(qp_run_address)//':'//zmq_port(2)//' '
  zmq_socket_pull_inproc_address = 'inproc://'//zmq_port(2)//' '
  zmq_socket_push_inproc_address = zmq_socket_pull_inproc_address
  zmq_socket_pair_inproc_address = 'inproc://'//zmq_port(3)//' '
end


subroutine switch_qp_run_to_master
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Address of the master qp_run socket
  ! Example : tcp://130.120.229.139:12345
  END_DOC
  character*(128)                :: buffer
  call getenv('QP_RUN_ADDRESS_MASTER',buffer)
  if (trim(buffer) == '') then
    print *,  'This run should be started with the qp_run command'
    stop -1
  endif
  qp_run_address = trim(buffer)
  print *,  'Switched to qp_run master : ', trim(qp_run_address)
  
  integer                        :: i
  do i=len(buffer),1,-1
    if ( buffer(i:i) == ':') then
      qp_run_address = trim(buffer(1:i-1))
      read(buffer(i+1:), *) zmq_port_start
      exit
    endif
  enddo
  call reset_zmq_addresses

end


function zmq_port(ishift)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Return the value of the ZMQ port from the corresponding integer
  END_DOC
  integer, intent(in)            :: ishift
  character*(8)                  :: zmq_port
  write(zmq_port,'(I8)') zmq_port_start+ishift
  zmq_port = adjustl(trim(zmq_port))
end


function new_zmq_to_qp_run_socket()
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket on which the qp_run process replies
  END_DOC
  integer                        :: rc
  character*(8), external        :: zmq_port
  integer(ZMQ_PTR)               :: new_zmq_to_qp_run_socket
  
  call omp_set_lock(zmq_lock)
  if (zmq_context == 0_ZMQ_PTR) then
     stop 'zmq_context is uninitialized'
  endif
  new_zmq_to_qp_run_socket = f77_zmq_socket(zmq_context, ZMQ_REQ)
  call omp_unset_lock(zmq_lock)
  if (new_zmq_to_qp_run_socket == 0_ZMQ_PTR) then
     stop 'Unable to create zmq req socket'
  endif

  rc = f77_zmq_setsockopt(new_zmq_to_qp_run_socket, ZMQ_SNDTIMEO, 120000, 4)
  if (rc /= 0) then
    stop 'Unable to set send timeout in new_zmq_to_qp_run_socket'
  endif

  rc = f77_zmq_setsockopt(new_zmq_to_qp_run_socket, ZMQ_RCVTIMEO, 120000, 4)
  if (rc /= 0) then
    stop 'Unable to set recv timeout in new_zmq_to_qp_run_socket'
  endif

  rc = f77_zmq_connect(new_zmq_to_qp_run_socket, trim(qp_run_address)//':'//trim(zmq_port(0)))
  if (rc /= 0) then
    stop 'Unable to connect new_zmq_to_qp_run_socket'
  endif

end


function new_zmq_pair_socket(bind)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket on which the collector and the main communicate 
  END_DOC
  logical                        :: bind
  integer                        :: rc
  character*(8), external        :: zmq_port
  integer(ZMQ_PTR)               :: new_zmq_pair_socket
  
  call omp_set_lock(zmq_lock)
  if (zmq_context == 0_ZMQ_PTR) then
     stop 'zmq_context is uninitialized'
  endif
  new_zmq_pair_socket = f77_zmq_socket(zmq_context, ZMQ_PAIR)
  call omp_unset_lock(zmq_lock)
  if (new_zmq_pair_socket == 0_ZMQ_PTR) then
     stop 'Unable to create zmq pair socket'
  endif


  rc = f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_SNDHWM, 1, 4)
  if (rc /= 0) then
    stop 'f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_SNDHWM, 1, 4)'
  endif

  rc = f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_RCVHWM, 1, 4)
  if (rc /= 0) then
    stop 'f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_RCVHWM, 1, 4)'
  endif

  rc = f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_IMMEDIATE, 1, 4)
  if (rc /= 0) then
    stop 'f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_IMMEDIATE, 1, 4)'
  endif

  rc = f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_LINGER, 600000, 4)
  if (rc /= 0) then
    stop 'f77_zmq_setsockopt(new_zmq_pair_socket, ZMQ_LINGER, 60000, 4)'
  endif

  if (bind) then
    rc = f77_zmq_bind(new_zmq_pair_socket,zmq_socket_pair_inproc_address)
    if (rc /= 0) then
      print *,  'f77_zmq_bind(new_zmq_pair_socket, zmq_socket_pair_inproc_address)'
      stop 'error'
    endif
  else
    rc = f77_zmq_connect(new_zmq_pair_socket,zmq_socket_pair_inproc_address)
    if (rc /= 0) then
      stop 'Unable to connect new_zmq_pair_socket'
    endif
  endif

end




function new_zmq_pull_socket()
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket on which the results are sent. If thread is 1, use inproc
  END_DOC
  integer                        :: rc
  character*(8), external        :: zmq_port
  integer(ZMQ_PTR)               :: new_zmq_pull_socket
  
  call omp_set_lock(zmq_lock)
  if (zmq_context == 0_ZMQ_PTR) then
     stop 'zmq_context is uninitialized'
  endif
  new_zmq_pull_socket = f77_zmq_socket(zmq_context, ZMQ_PULL)
!  new_zmq_pull_socket = f77_zmq_socket(zmq_context, ZMQ_REP)
  call omp_unset_lock(zmq_lock)
  if (new_zmq_pull_socket == 0_ZMQ_PTR) then
     stop 'Unable to create zmq pull socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_pull_socket,ZMQ_LINGER,300000,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_LINGER on pull socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_pull_socket,ZMQ_RCVBUF,100000000,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_RCVBUF on pull socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_pull_socket,ZMQ_RCVHWM,1,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_RCVHWM on pull socket'
  endif
  
  integer :: icount

  icount = 10
  do while (icount > 0)
    rc = f77_zmq_bind(new_zmq_pull_socket, zmq_socket_pull_inproc_address)
    if (rc /= 0) then
      icount = icount-1
      call sleep(3)
    else
      exit
    endif
  enddo

  if (icount == 0) then
    print *,  'Unable to bind new_zmq_pull_socket (inproc)', zmq_socket_pull_inproc_address
    stop -1
  endif


  icount = 10
  do while (icount > 0)
    rc = f77_zmq_bind(new_zmq_pull_socket, zmq_socket_pull_tcp_address)
    if (rc /= 0) then
      icount = icount-1
      call sleep(3)
    else
      exit
    endif
  enddo

  if (icount == 0) then
    print *,  'Unable to bind new_zmq_pull_socket (tcp)', zmq_socket_pull_tcp_address
    stop -1
  endif
  
end




function new_zmq_push_socket(thread)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket on which the results are sent. If thread is 1, use inproc
  END_DOC
  integer, intent(in)            :: thread
  integer                        :: rc
  character*(8), external        :: zmq_port
  integer(ZMQ_PTR)               :: new_zmq_push_socket
  
  call omp_set_lock(zmq_lock)
  if (zmq_context == 0_ZMQ_PTR) then
     stop 'zmq_context is uninitialized'
  endif
  new_zmq_push_socket = f77_zmq_socket(zmq_context, ZMQ_PUSH)
!  new_zmq_push_socket = f77_zmq_socket(zmq_context, ZMQ_REQ)
  call omp_unset_lock(zmq_lock)
  if (new_zmq_push_socket == 0_ZMQ_PTR) then
     stop 'Unable to create zmq push socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_push_socket,ZMQ_LINGER,300000,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_LINGER on push socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_push_socket,ZMQ_SNDHWM,1,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_SNDHWM on push socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_push_socket,ZMQ_SNDBUF,100000000,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_RCVBUF on push socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_push_socket,ZMQ_IMMEDIATE,1,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_IMMEDIATE on push socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_push_socket, ZMQ_SNDTIMEO, 100000, 4)
  if (rc /= 0) then
    stop 'Unable to set send timout in new_zmq_push_socket'
  endif
  
  if (thread == 1) then
    rc = f77_zmq_connect(new_zmq_push_socket, zmq_socket_push_inproc_address)
  else
    rc = f77_zmq_connect(new_zmq_push_socket, zmq_socket_push_tcp_address)
  endif
  if (rc /= 0) then
    stop 'Unable to connect new_zmq_push_socket'
  endif
  
end



function new_zmq_sub_socket()
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Socket to read the state published by the Task server
  END_DOC
  integer                        :: rc
  integer(ZMQ_PTR)               :: new_zmq_sub_socket
  
  call omp_set_lock(zmq_lock)
  if (zmq_context == 0_ZMQ_PTR) then
     stop 'zmq_context is uninitialized'
  endif
  new_zmq_sub_socket = f77_zmq_socket(zmq_context, ZMQ_SUB)
  call omp_unset_lock(zmq_lock)
  if (new_zmq_sub_socket == 0_ZMQ_PTR) then
     stop 'Unable to create zmq sub socket'
  endif
  
  rc = f77_zmq_setsockopt(new_zmq_sub_socket,ZMQ_RCVTIMEO,10000,4)
  if (rc /= 0) then
    stop 'Unable to set timeout in new_zmq_sub_socket'
  endif

  rc = f77_zmq_setsockopt(new_zmq_sub_socket,ZMQ_CONFLATE,1,4)
  if (rc /= 0) then
    stop 'Unable to set conflate in new_zmq_sub_socket'
  endif

  rc = f77_zmq_setsockopt(new_zmq_sub_socket,ZMQ_SUBSCRIBE,"",0)
  if (rc /= 0) then
    stop 'Unable to subscribe new_zmq_sub_socket'
  endif

  rc = f77_zmq_connect(new_zmq_sub_socket, zmq_socket_sub_tcp_address)
  if (rc /= 0) then
    stop 'Unable to connect new_zmq_sub_socket'
  endif
end


subroutine end_zmq_sub_socket(zmq_socket_sub)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Terminate socket on which the results are sent.
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_socket_sub
  integer                        :: rc
  
  rc = f77_zmq_close(zmq_socket_sub)
  if (rc /= 0) then
    print *,  'f77_zmq_close(zmq_socket_sub)'
    stop 'error'
  endif
  
end


subroutine end_zmq_pair_socket(zmq_socket_pair)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Terminate socket on which the results are sent.
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_socket_pair
  integer                        :: rc
  character*(8), external        :: zmq_port
  
  rc = f77_zmq_close(zmq_socket_pair)
  if (rc /= 0) then
    print *,  'f77_zmq_close(zmq_socket_pair)'
    stop 'error'
  endif
  
end

subroutine end_zmq_pull_socket(zmq_socket_pull)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Terminate socket on which the results are sent.
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_socket_pull
  integer                        :: rc
  character*(8), external        :: zmq_port
  
  rc = f77_zmq_close(zmq_socket_pull)
  if (rc /= 0) then
    print *,  'f77_zmq_close(zmq_socket_pull)'
    stop 'error'
  endif
  
end


subroutine end_zmq_push_socket(zmq_socket_push,thread)
  implicit none
  use f77_zmq
  BEGIN_DOC
  ! Terminate socket on which the results are sent.
  END_DOC
  integer, intent(in)            :: thread
  integer(ZMQ_PTR), intent(in)   :: zmq_socket_push
  integer                        :: rc
  character*(8), external        :: zmq_port
  
  rc = f77_zmq_setsockopt(zmq_socket_push,ZMQ_LINGER,300000,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_LINGER on push socket'
  endif

  rc = f77_zmq_close(zmq_socket_push)
  if (rc /= 0) then
    print *,  'f77_zmq_close(zmq_socket_push)'
    stop 'error'
  endif
  
end



BEGIN_PROVIDER [ character*(128), zmq_state ]
  implicit none
  BEGIN_DOC
  ! Threads executing work through the ZeroMQ interface
  END_DOC
  zmq_state = 'No_state'
END_PROVIDER

subroutine new_parallel_job(zmq_to_qp_run_socket,name_in)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Start a new parallel job with name 'name'. The slave tasks execute subroutine 'slave'
  END_DOC
  character*(*), intent(in)      :: name_in
  
  character*(512)                :: message, name
  integer                        :: rc, sze
  integer(ZMQ_PTR),external      :: new_zmq_to_qp_run_socket
  integer(ZMQ_PTR), intent(out)  :: zmq_to_qp_run_socket

  zmq_context = f77_zmq_ctx_new ()
  if (zmq_context == 0_ZMQ_PTR) then
     stop 'ZMQ_PTR is null'
  endif
  zmq_to_qp_run_socket = new_zmq_to_qp_run_socket()
  name = name_in
  sze = len(trim(name))
  call lowercase(name,sze)
  message = 'new_job '//trim(name)//' '//zmq_socket_push_tcp_address//' '//zmq_socket_pull_inproc_address
  sze = len(trim(message))
  rc = f77_zmq_send(zmq_to_qp_run_socket,message,sze,0)
  if (rc /= sze) then
    print *,  irp_here, ':f77_zmq_send(zmq_to_qp_run_socket,message,sze,0)'
    stop 'error'
  endif
  rc = f77_zmq_recv(zmq_to_qp_run_socket,message,510,0)
  message = trim(message(1:rc))
  if (message(1:2) /= 'ok') then
    print *,  message
    print *,  'Unable to start parallel job : '//name
    stop 1
  endif
  
  zmq_state = trim(name)
  
end

subroutine zmq_set_running(zmq_to_qp_run_socket)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Set the job to Running in QP-run
  END_DOC
  
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  character*(512)                :: message
  integer                        :: rc, sze

  message = 'set_running'
  sze = len(trim(message))
  rc = f77_zmq_send(zmq_to_qp_run_socket,message,sze,0)
  if (rc /= sze) then
    print *,  irp_here, ':f77_zmq_send(zmq_to_qp_run_socket,message,sze,0)'
    stop 'error'
  endif
  rc = f77_zmq_recv(zmq_to_qp_run_socket,message,510,0)
  message = trim(message(1:rc))
  if (message(1:2) /= 'ok') then
    print *,  'Unable to set qp_run to Running'
    stop 1
  endif
  
  
end


subroutine end_parallel_job(zmq_to_qp_run_socket,name_in)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! End a new parallel job with name 'name'. The slave tasks execute subroutine 'slave'
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  character*(*), intent(in)      :: name_in

  character*(512)                :: message, name
  integer                        :: i,rc, sze

  name = name_in
  sze = len(trim(name))
  call lowercase(name,sze)
  if (name /= zmq_state) then
    stop 'Wrong end of job'
  endif

  rc = f77_zmq_send(zmq_to_qp_run_socket, 'end_job '//trim(zmq_state),8+len(trim(zmq_state)),0)
  rc = f77_zmq_recv(zmq_to_qp_run_socket, zmq_state, 2, 0)
  if (rc /= 2) then
    print *,  'f77_zmq_recv(zmq_to_qp_run_socket, zmq_state, 2, 0)'
    stop 'error'
  endif
  zmq_state = 'No_state'
  call end_zmq_to_qp_run_socket(zmq_to_qp_run_socket)

  rc = f77_zmq_ctx_term(zmq_context)
  if (rc /= 0) then
    print *,  'Unable to terminate ZMQ context'
    stop 'error'
  endif
end

subroutine connect_to_taskserver(zmq_to_qp_run_socket,worker_id,thread)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Connect to the task server and obtain the worker ID
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  integer, intent(out)           :: worker_id
  integer, intent(in)            :: thread
  
  character*(512)                :: message
  character*(128)                :: reply, state, address
  integer                        :: rc
  if (thread == 1) then
    rc = f77_zmq_send(zmq_to_qp_run_socket, "connect inproc", 14, 0)
    if (rc /= 14) then
      print *,  'f77_zmq_send(zmq_to_qp_run_socket, "connect inproc", 14, 0)'
      stop 'error'
    endif
  else
    rc = f77_zmq_send(zmq_to_qp_run_socket, "connect tcp", 11, 0)
    if (rc /= 11) then
      print *,  'f77_zmq_send(zmq_to_qp_run_socket, "connect tcp", 11, 0)'
      stop 'error'
    endif
  endif
  
  rc = f77_zmq_recv(zmq_to_qp_run_socket, message, 510, 0)
  message = trim(message(1:rc))
  if(message(1:5) == "error") then
    worker_id = -1
    return
  end if
  read(message,*) reply, state, worker_id, address
  if ( (trim(reply) /= 'connect_reply') .and.                        &
        (trim(state) /= trim(zmq_state)) ) then
    print *,  'Reply: ', trim(reply)
    print *,  'State: ', trim(state), '/', trim(zmq_state)
    print *,  'Address: ', trim(address)
    stop -1
  endif
end

subroutine disconnect_from_taskserver(zmq_to_qp_run_socket, &
   zmq_socket_push, worker_id)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Disconnect from the task server
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  integer(ZMQ_PTR), intent(in)   :: zmq_socket_push
  integer, intent(in)            :: worker_id
  
  integer                        :: rc, sze
  character*(64)                 :: message, reply, state
  write(message,*) 'disconnect '//trim(zmq_state), worker_id
  
  sze = len(trim(message))
  rc = f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)
  if (rc /= sze) then
    print *,  rc, sze
    print *,  irp_here, 'f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)'
    stop 'error'
  endif
  
  rc = f77_zmq_recv(zmq_to_qp_run_socket, message, 510, 0)
  message = trim(message(1:rc))
  
  read(message,*) reply, state
  if ((trim(reply) == 'disconnect_reply').and.(trim(state) == trim(zmq_state))) then
    return
  endif
  if (trim(message) == 'error No job is running') then
    return
  endif

  print *,  'Unable to disconnect : ', trim(zmq_state)
  print *,  trim(message)
  stop -1

end

subroutine add_task_to_taskserver(zmq_to_qp_run_socket,task)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Get a task from the task server
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  character*(*), intent(in)      :: task
  
  integer                        :: rc, sze
  character*(512)                :: message
  write(message,*) 'add_task '//trim(zmq_state)//' '//trim(task)
  
  sze = len(trim(message))
  rc = f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)
  if (rc /= sze) then
    print *,  rc, sze
    print *,  irp_here,': f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)'
    stop 'error'
  endif
  
  rc = f77_zmq_recv(zmq_to_qp_run_socket, message, 510, 0)
  message = trim(message(1:rc))
  if (trim(message) /= 'ok') then
    print *,  trim(task)
    print *,  'Unable to add the next task'
    stop -1
  endif
  
end

subroutine task_done_to_taskserver(zmq_to_qp_run_socket, worker_id, task_id)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Get a task from the task server
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  integer, intent(in)            :: worker_id, task_id 
  
  integer                        :: rc, sze
  character*(512)                :: message
  write(message,*) 'task_done '//trim(zmq_state), worker_id, task_id
  
  sze = len(trim(message))
  rc = f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)
  if (rc /= sze) then
    print *,  irp_here, 'f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)'
    stop 'error'
  endif
  
  rc = f77_zmq_recv(zmq_to_qp_run_socket, message, 510, 0)
  message = trim(message(1:rc))
  if (trim(message) /= 'ok') then
    print *,  'Unable to send task_done message'
    stop -1
  endif
  
end

subroutine get_task_from_taskserver(zmq_to_qp_run_socket,worker_id,task_id,task)
  use f77_zmq
  implicit none
  BEGIN_DOC
  ! Get a task from the task server
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  integer, intent(in)            :: worker_id
  integer, intent(out)           :: task_id
  character*(512), intent(out)   :: task
  
  character*(512)                :: message
  character*(64)                 :: reply
  integer                        :: rc, sze
  
  write(message,*) 'get_task '//trim(zmq_state), worker_id
  
  sze = len(trim(message))
  rc = f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)
  if (rc /= sze) then
    print *,  irp_here, ':f77_zmq_send(zmq_to_qp_run_socket, trim(message), sze, 0)'
    stop 'error'
  endif
  
  rc = f77_zmq_recv(zmq_to_qp_run_socket, message, 510, 0)
  message = trim(message(1:rc))
  read(message,*) reply
  if (trim(reply) == 'get_task_reply') then
    read(message,*) reply, task_id
    rc = 15
    do while (message(rc:rc) == ' ')
      rc += 1
    enddo
    do while (message(rc:rc) /= ' ')
      rc += 1
    enddo
    rc += 1
    task = message(rc:)
  else if (trim(reply) == 'terminate') then
    task_id = 0
    task = 'terminate'
  else if (trim(message) == 'error No job is running') then
    task_id = 0
    task = 'terminate'
  else
    print *,  'Unable to get the next task'
    print *,  trim(message)
    stop -1
  endif
  
end


subroutine end_zmq_to_qp_run_socket(zmq_to_qp_run_socket)
  use f77_zmq
  implicit none
  BEGIN_DOC
! Terminate the socket from the application to qp_run
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  character*(8), external        :: zmq_port
  integer                        :: rc

  rc = f77_zmq_setsockopt(zmq_to_qp_run_socket,ZMQ_LINGER,1000,4)
  if (rc /= 0) then
    stop 'Unable to set ZMQ_LINGER on zmq_to_qp_run_socket'
  endif

  rc = f77_zmq_close(zmq_to_qp_run_socket)
  if (rc /= 0) then
    print *,  'f77_zmq_close(zmq_to_qp_run_socket)'
    stop 'error'
  endif
  
end

subroutine zmq_delete_task(zmq_to_qp_run_socket,zmq_socket_pull,task_id,more)
  use f77_zmq
  implicit none
  BEGIN_DOC
! When a task is done, it has to be removed from the list of tasks on the qp_run
! queue. This guarantees that the results have been received in the pull.
  END_DOC
  integer(ZMQ_PTR), intent(in)   :: zmq_to_qp_run_socket
  integer(ZMQ_PTR)               :: zmq_socket_pull
  integer, intent(in)            :: task_id
  integer, intent(out)           :: more
  integer                        :: rc
  character*(512)                :: msg

  write(msg,*) 'del_task ', zmq_state, task_id
  rc = f77_zmq_send(zmq_to_qp_run_socket,msg,512,0)
  if (rc /= 512) then
    print *,  'f77_zmq_send(zmq_to_qp_run_socket,task_id,4,0)'
    stop 'error'
  endif

  character*(64) :: reply
  reply = ''
  rc = f77_zmq_recv(zmq_to_qp_run_socket,reply,64,0)

  if (reply(16:19) == 'more') then
    more = 1
  else if (reply(16:19) == 'done') then
    more = 0
    rc = f77_zmq_setsockopt(zmq_socket_pull, ZMQ_RCVTIMEO, 1000, 4)
    if (rc /= 0) then
       print *,  'f77_zmq_setsockopt(zmq_socket_pull, ZMQ_RCVTIMEO, 3000, 4)'
       stop 'error'
    endif
  else
    print *,  reply
    print *,  'f77_zmq_recv(zmq_to_qp_run_socket,reply,64,0)'
    stop 'error'
  endif
end


subroutine wait_for_next_state(state)
  use f77_zmq
  implicit none

  character*(64), intent(out)    :: state
  integer(ZMQ_PTR)               :: zmq_socket_sub
  integer(ZMQ_PTR), external     :: new_zmq_sub_socket
  integer                        :: rc

  zmq_socket_sub       = new_zmq_sub_socket()
  state = 'Waiting'
  do while(state == "Waiting")
    rc = f77_zmq_recv( zmq_socket_sub, state, 64, 0)
    if (rc > 0) then
      state = trim(state(1:rc))
    else
      print *,  'Timeout reached. Stopping'
      state = "Stopped"
    end if 
  end do
  call end_zmq_sub_socket(zmq_socket_sub)
end subroutine


subroutine wait_for_state(state_wait,state)
  use f77_zmq
  implicit none
  BEGIN_DOC
! Wait for the ZMQ state to be ready
  END_DOC
  character*(64), intent(in)     :: state_wait
  character*(64), intent(out)    :: state
  integer(ZMQ_PTR)               :: zmq_socket_sub
  integer(ZMQ_PTR), external     :: new_zmq_sub_socket
  integer                        :: rc

  zmq_socket_sub       = new_zmq_sub_socket()
  state = 'Waiting'
  do while (trim(state) /= trim(state_wait) .and. trim(state) /= 'Stopped')
    rc = f77_zmq_recv( zmq_socket_sub, state, 64, 0)
    if (rc > 0) then
      state = trim(state(1:rc))
    else
      print *,  'Timeout reached. Stopping'
      state = "Stopped"
    endif
  end do
  call end_zmq_sub_socket(zmq_socket_sub)
end



subroutine wait_for_states(state_wait,state,n)
  use f77_zmq
  implicit none
  BEGIN_DOC
! Wait for the ZMQ state to be ready
  END_DOC
  integer, intent(in)            :: n
  character*(64), intent(in)     :: state_wait(n)
  character*(64), intent(out)    :: state
  integer(ZMQ_PTR)               :: zmq_socket_sub
  integer(ZMQ_PTR), external     :: new_zmq_sub_socket
  integer                        :: rc, i
  logical                        :: condition

  zmq_socket_sub       = new_zmq_sub_socket()
  state = 'Waiting'
  condition = .True.
  do while (condition)
    rc = f77_zmq_recv( zmq_socket_sub, state, 64, 0)
    if (rc > 0) then
      state = trim(state(1:rc))
    else
      print *,  'Timeout reached. Stopping'
      state = "Stopped"
    endif
    condition = trim(state) /= 'Stopped'
    do i=1,n
      condition = condition .and. (trim(state) /= trim(state_wait(i)))
    enddo
  end do
  call end_zmq_sub_socket(zmq_socket_sub)
end


