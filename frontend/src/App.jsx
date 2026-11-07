import { useEffect, useState } from 'react'

export default function App() {
  const [info, setInfo] = useState({ message: 'loading...', env: '' })

  useEffect(() => {
    fetch('/api/message')
      .then((res) => res.json())
      .then((data) => setInfo(data))
      .catch(() => setInfo({ message: 'failed to reach backend', env: '' }))
  }, [])

  return (
    <main style={{ fontFamily: 'sans-serif', padding: '2rem' }}>
      <h1>Fullstack GitHub Template</h1>
      <p>
        Backend says: <strong>{info.message}</strong>
      </p>
      <p>
        Environment: <strong>{info.env || '—'}</strong>
      </p>
    </main>
  )
}
