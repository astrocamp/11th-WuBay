import React , { useRef , useState} from 'react'

const DropDownList = () => {
  const selectForm = useRef()
  const handleSubmit = () => {selectForm.current.submit()}
  const [optionSelected, setOptionSelected] = useState('')
  let querystring = (new URL(document.location)).searchParams;
  let params = querystring.get('type')
  return (
    <div>
      <form action="/projects" method="get" ref={selectForm} onChange={handleSubmit} >
        <select name="type" id="type" className='p-2 pr-5 rounded-md border border-blue-400 border-solid focus:outline-none focus:ring focus:border-blue-300'>
          <option>全部主題</option>
          <option value="origin">原創設計</option>
          <option value="society" >社會公益</option>
          <option value="independence">獨立集資</option>
        </select>
      </form>
    </div>
  )
}

export default DropDownList
